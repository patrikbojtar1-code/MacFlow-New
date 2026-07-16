//
//  SystemCallActivitySource.swift
//  NotchLand
//
//  Detects FaceTime and iPhone Continuity call banners through the public
//  macOS Accessibility API. The scanner limits itself to call-related system
//  apps, classifies each window independently and discards unrelated content.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
struct SystemCallDetection {
    let callerName: String
    let serviceName: String
    let answerAction: (@MainActor @Sendable () -> Void)?
    let declineAction: (@MainActor @Sendable () -> Void)?

    var fingerprint: String {
        "\(callerName.foldingForCallDetection)|\(serviceName.foldingForCallDetection)"
    }
}

nonisolated enum SystemCallWindowClassifier {
    struct Result: Equatable, Sendable {
        let callerName: String
        let serviceName: String
        let answerButtonIndex: Int?
        let declineButtonIndex: Int?
    }

    private static let callMarkers = [
        "from your iphone", "z vaseho iphonu", "von deinem iphone",
        "de votre iphone", "dal tuo iphone", "desde tu iphone",
        "incoming call", "prichozi hovor", "facetime audio", "facetime video",
    ]
    private static let answerTokens = [
        "answer", "accept", "prijmout", "zvednout", "annehmen", "accepter", "rispondi",
    ]
    private static let declineTokens = [
        "decline", "reject", "odmitnout", "hang up", "ablehnen", "refuser", "rifiuta",
    ]
    private static let ignoredCallerValues = [
        "facetime", "iphone", "incoming call", "prichozi hovor", "answer", "accept",
        "decline", "reject", "prijmout", "odmitnout", "zvednout", "vice", "more",
    ]

    static func classify(
        textValues: [String],
        buttonLabels: [String],
        ownerName: String
    ) -> Result? {
        let normalizedText = textValues.map(\.foldingForCallDetection)
        let normalizedButtons = buttonLabels.map(\.foldingForCallDetection)
        let combined = (normalizedText + normalizedButtons).joined(separator: " ")

        let answerIndex = normalizedButtons.firstIndex { label in
            answerTokens.contains { label.contains($0) }
        }
        let declineIndex = normalizedButtons.firstIndex { label in
            declineTokens.contains { label.contains($0) }
        }
        let hasCallMarker = callMarkers.contains { combined.contains($0) }
        guard hasCallMarker || (answerIndex != nil && declineIndex != nil) else { return nil }

        let owner = ownerName.foldingForCallDetection
        let caller = textValues.first { value in
            let normalized = value.foldingForCallDetection
            guard !normalized.isEmpty, normalized.count <= 80 else { return false }
            guard normalized != owner else { return false }
            guard !callMarkers.contains(where: { normalized.contains($0) }) else { return false }
            guard !ignoredCallerValues.contains(where: { normalized == $0 || normalized.contains("\($0) button") }) else {
                return false
            }
            return true
        } ?? "Unknown Caller"

        let service: String
        if combined.contains("iphone") || combined.contains("iphonu") {
            service = "iPhone Continuity"
        } else if combined.contains("facetime") || owner.contains("facetime") {
            service = "FaceTime"
        } else {
            service = "System Call"
        }

        return Result(
            callerName: caller,
            serviceName: service,
            answerButtonIndex: answerIndex,
            declineButtonIndex: declineIndex
        )
    }
}

@MainActor
protocol SystemCallScanning {
    func detectCall() -> SystemCallDetection?
}

@MainActor
final class AccessibilitySystemCallScanner: SystemCallScanning {
    private final class ButtonAction {
        let element: AXUIElement

        init(element: AXUIElement) {
            self.element = element
        }

        func perform() {
            _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
        }
    }

    private struct WindowSnapshot {
        var textValues: [String] = []
        var buttons: [(label: String, element: AXUIElement)] = []
    }

    private static let candidateBundleFragments = [
        "facetime", "notificationcenter", "usernotification", "continuity", "callui",
    ]
    private static let candidateNameFragments = [
        "facetime", "notification center", "notificationcenter", "continuity",
    ]
    private static let maximumElementsPerWindow = 260
    private static let maximumTreeDepth = 9

    func detectCall() -> SystemCallDetection? {
        guard AXIsProcessTrusted() else { return nil }

        for application in NSWorkspace.shared.runningApplications where isCandidate(application) {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            let windows = elementArrayAttribute(kAXWindowsAttribute, from: appElement)
            for window in windows {
                let snapshot = snapshot(of: window)
                guard let result = SystemCallWindowClassifier.classify(
                    textValues: snapshot.textValues,
                    buttonLabels: snapshot.buttons.map(\.label),
                    ownerName: application.localizedName ?? ""
                ) else { continue }

                let answer = result.answerButtonIndex.flatMap { snapshot.buttons[safe: $0]?.element }
                let decline = result.declineButtonIndex.flatMap { snapshot.buttons[safe: $0]?.element }
                return SystemCallDetection(
                    callerName: result.callerName,
                    serviceName: result.serviceName,
                    answerAction: answer.map(action(for:)),
                    declineAction: decline.map(action(for:))
                )
            }
        }
        return nil
    }

    private func isCandidate(_ application: NSRunningApplication) -> Bool {
        let bundle = application.bundleIdentifier?.lowercased() ?? ""
        let name = application.localizedName?.lowercased() ?? ""
        return Self.candidateBundleFragments.contains(where: bundle.contains)
            || Self.candidateNameFragments.contains(where: name.contains)
    }

    private func snapshot(of root: AXUIElement) -> WindowSnapshot {
        var result = WindowSnapshot()
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0

        while index < queue.count, index < Self.maximumElementsPerWindow {
            let (element, depth) = queue[index]
            index += 1

            let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
            let values = readableStrings(from: element)
            if role == kAXStaticTextRole as String || role == kAXHeadingRole as String {
                result.textValues.append(contentsOf: values)
            } else if role == kAXButtonRole as String {
                let label = values.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                result.buttons.append((label.isEmpty ? "button" : label, element))
            }

            if depth < Self.maximumTreeDepth {
                queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute, from: element).map { ($0, depth + 1) })
            }
        }

        result.textValues = result.textValues.uniquedCallStrings()
        return result
    }

    private func readableStrings(from element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            .compactMap { stringAttribute($0, from: element) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .uniquedCallStrings()
    }

    private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func elementArrayAttribute(_ name: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let values = value as? [AXUIElement] else { return [] }
        return values
    }

    private func action(for element: AXUIElement) -> @MainActor @Sendable () -> Void {
        let action = ButtonAction(element: element)
        return { action.perform() }
    }
}

@MainActor
final class SystemCallActivitySource: ObservableObject {
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var hasRequestedAccessibilityThisRun = false

    private static let pollInterval: TimeInterval = 0.35
    private static let missingPollLimit = 3

    private let calls: CallActivityController
    private let settings: NotchSettings
    private let scanner: any SystemCallScanning
    private var timer: Timer?
    private var activeFingerprint: String?
    private var activeCallID: UUID?
    private var missingPolls = 0

    convenience init(calls: CallActivityController, settings: NotchSettings) {
        self.init(calls: calls, settings: settings, scanner: AccessibilitySystemCallScanner())
    }

    init(
        calls: CallActivityController,
        settings: NotchSettings,
        scanner: any SystemCallScanning
    ) {
        self.calls = calls
        self.settings = settings
        self.scanner = scanner
    }

    func start() {
        guard timer == nil else { return }
        // Never show the system consent dialog automatically on launch. The
        // prompt is reserved for an explicit user action in Settings/onboarding.
        refreshPermissionStatus()
        poll()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activeFingerprint = nil
        activeCallID = nil
        missingPolls = 0
    }

    func requestAccessibilityPermission() {
        refreshPermissionStatus()
        guard !isAccessibilityTrusted, !hasRequestedAccessibilityThisRun else { return }
        hasRequestedAccessibilityThisRun = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func refreshPermissionStatus() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    private func poll() {
        let trusted = AXIsProcessTrusted()
        if trusted != isAccessibilityTrusted { isAccessibilityTrusted = trusted }
        guard settings.systemCallDetectionEnabled, trusted else {
            resetDetectionState(dismissIncoming: false)
            return
        }

        if let detection = scanner.detectCall() {
            missingPolls = 0
            guard detection.fingerprint != activeFingerprint else { return }
            activeFingerprint = detection.fingerprint
            calls.receiveIncoming(
                callerName: detection.callerName,
                serviceName: detection.serviceName,
                supportsCallControl: detection.answerAction != nil && detection.declineAction != nil,
                onAnswer: detection.answerAction,
                onDecline: detection.declineAction
            )
            activeCallID = calls.current?.id
        } else if activeFingerprint != nil {
            missingPolls += 1
            if missingPolls >= Self.missingPollLimit {
                if let activeCallID {
                    calls.systemCallBannerDidDisappear(id: activeCallID)
                }
                resetDetectionState(dismissIncoming: false)
            }
        }
    }

    private func resetDetectionState(dismissIncoming: Bool) {
        if dismissIncoming, let activeCallID {
            calls.systemCallBannerDidDisappear(id: activeCallID)
        }
        activeFingerprint = nil
        activeCallID = nil
        missingPolls = 0
    }
}

private extension String {
    nonisolated var foldingForCallDetection: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array where Element == String {
    nonisolated func uniquedCallStrings() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Array {
    nonisolated subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
