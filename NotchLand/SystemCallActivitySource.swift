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

nonisolated struct SystemAccessibilityApplicationDescriptor: Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let localizedName: String
}

/// AXUIElement is an immutable Core Foundation reference. Access is confined to
/// the background scanner except for the explicit press action, which is
/// performed on MainActor in response to a user click.
nonisolated final class SystemAccessibilityPressHandle: @unchecked Sendable {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    @MainActor
    func perform() {
        _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

nonisolated struct SystemAccessibilityButtonSnapshot: Sendable {
    let label: String
    let pressHandle: SystemAccessibilityPressHandle
}

nonisolated struct SystemAccessibilityWindowSnapshot: Sendable {
    let ownerBundleIdentifier: String
    let ownerName: String
    let textValues: [String]
    let buttons: [SystemAccessibilityButtonSnapshot]
}

nonisolated struct SystemAccessibilityActivitySnapshot: Sendable {
    let windows: [SystemAccessibilityWindowSnapshot]

    static let empty = SystemAccessibilityActivitySnapshot(windows: [])
}

/// Performs the blocking Accessibility traversal away from MainActor. One
/// snapshot feeds both call and message classification, preventing duplicate
/// walks over Notification Center's accessibility tree.
actor SystemAccessibilitySnapshotScanner {
    private static let maximumElementsPerWindow = 260
    private static let maximumTreeDepth = 9
    private static let maximumWindowsPerApplication = 12

    func scan(
        applications: [SystemAccessibilityApplicationDescriptor]
    ) -> SystemAccessibilityActivitySnapshot {
        var windows: [SystemAccessibilityWindowSnapshot] = []
        for application in applications {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            for window in elementArrayAttribute(kAXWindowsAttribute, from: appElement)
                .prefix(Self.maximumWindowsPerApplication) {
                windows.append(snapshot(of: window, owner: application))
            }
        }
        return SystemAccessibilityActivitySnapshot(windows: windows)
    }

    private func snapshot(
        of root: AXUIElement,
        owner: SystemAccessibilityApplicationDescriptor
    ) -> SystemAccessibilityWindowSnapshot {
        var textValues: [String] = []
        var buttons: [SystemAccessibilityButtonSnapshot] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0

        while index < queue.count, index < Self.maximumElementsPerWindow {
            let (element, depth) = queue[index]
            index += 1

            let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
            let values = readableStrings(from: element)
            if role == kAXStaticTextRole as String || role == kAXHeadingRole as String {
                textValues.append(contentsOf: values)
            } else if role == kAXButtonRole as String {
                let label = values.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                buttons.append(
                    SystemAccessibilityButtonSnapshot(
                        label: label.isEmpty ? "button" : label,
                        pressHandle: SystemAccessibilityPressHandle(element: element)
                    )
                )
            }

            if depth < Self.maximumTreeDepth {
                queue.append(contentsOf: elementArrayAttribute(kAXChildrenAttribute, from: element).map { ($0, depth + 1) })
            }
        }

        return SystemAccessibilityWindowSnapshot(
            ownerBundleIdentifier: owner.bundleIdentifier,
            ownerName: owner.localizedName,
            textValues: textValues.uniquedCallStrings(),
            buttons: buttons
        )
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
}

nonisolated enum SystemActivityScanCadence {
    static let active: TimeInterval = 0.30
    static let idle: TimeInterval = 0.80
    static let unavailable: TimeInterval = 2.0

    static func interval(isAvailable: Bool, containsActivity: Bool) -> TimeInterval {
        guard isAvailable else { return unavailable }
        return containsActivity ? active : idle
    }
}

@MainActor
final class SystemAccessibilityActivityMonitor {
    private static let candidateBundleFragments = [
        "facetime", "notificationcenter", "usernotification", "continuity", "callui",
    ]
    private static let candidateNameFragments = [
        "facetime", "notification center", "notificationcenter", "continuity",
    ]

    private let calls: SystemCallActivitySource
    private let messages: SystemMessageActivitySource
    private let settings: NotchSettings
    private let scanner: SystemAccessibilitySnapshotScanner
    private var monitoringTask: Task<Void, Never>?

    init(
        calls: SystemCallActivitySource,
        messages: SystemMessageActivitySource,
        settings: NotchSettings,
        scanner: SystemAccessibilitySnapshotScanner = SystemAccessibilitySnapshotScanner()
    ) {
        self.calls = calls
        self.messages = messages
        self.settings = settings
        self.scanner = scanner
    }

    func start() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { @MainActor [weak self] in
            await self?.monitor()
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        calls.consume(snapshot: .empty, isAccessibilityTrusted: AXIsProcessTrusted())
        messages.consume(snapshot: .empty, isAccessibilityTrusted: AXIsProcessTrusted())
    }

    private func monitor() async {
        while !Task.isCancelled {
            let trusted = AXIsProcessTrusted()
            let isAvailable = settings.systemCallDetectionEnabled && trusted
            calls.updatePermissionStatus(isTrusted: trusted)

            let snapshot: SystemAccessibilityActivitySnapshot
            if isAvailable {
                snapshot = await scanner.scan(applications: candidateApplications())
                guard !Task.isCancelled else { return }
            } else {
                snapshot = .empty
            }

            calls.consume(snapshot: snapshot, isAccessibilityTrusted: trusted)
            messages.consume(snapshot: snapshot, isAccessibilityTrusted: trusted)

            let containsActivity = snapshot.windows.contains { window in
                SystemCallWindowClassifier.classify(
                    textValues: window.textValues,
                    buttonLabels: window.buttons.map(\.label),
                    ownerName: window.ownerName
                ) != nil || SystemMessageWindowClassifier.classify(textValues: window.textValues) != nil
            }
            let delay = SystemActivityScanCadence.interval(
                isAvailable: isAvailable,
                containsActivity: containsActivity
            )
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func candidateApplications() -> [SystemAccessibilityApplicationDescriptor] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            let bundle = application.bundleIdentifier?.lowercased() ?? ""
            let name = application.localizedName?.lowercased() ?? ""
            let isCandidate = Self.candidateBundleFragments.contains(where: bundle.contains)
                || Self.candidateNameFragments.contains(where: name.contains)
            guard isCandidate else { return nil }
            return SystemAccessibilityApplicationDescriptor(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: bundle,
                localizedName: application.localizedName ?? ""
            )
        }
    }
}

@MainActor
final class SystemCallActivitySource: ObservableObject {
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var hasRequestedAccessibilityThisRun = false

    private static let missingPollLimit = 3

    private let calls: CallActivityController
    private let settings: NotchSettings
    private var activeFingerprint: String?
    private var activeCallID: UUID?
    private var missingPolls = 0

    init(calls: CallActivityController, settings: NotchSettings) {
        self.calls = calls
        self.settings = settings
    }

    func start() {
        // Never show the system consent dialog automatically on launch. The
        // prompt is reserved for an explicit user action in Settings/onboarding.
        refreshPermissionStatus()
    }

    func stop() {
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

    func updatePermissionStatus(isTrusted: Bool) {
        if isTrusted != isAccessibilityTrusted {
            isAccessibilityTrusted = isTrusted
        }
    }

    func consume(
        snapshot: SystemAccessibilityActivitySnapshot,
        isAccessibilityTrusted trusted: Bool
    ) {
        updatePermissionStatus(isTrusted: trusted)
        guard settings.systemCallDetectionEnabled, trusted else {
            resetDetectionState(dismissIncoming: false)
            return
        }

        if let detection = detection(in: snapshot) {
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

    private func detection(in snapshot: SystemAccessibilityActivitySnapshot) -> SystemCallDetection? {
        for window in snapshot.windows {
            guard let result = SystemCallWindowClassifier.classify(
                textValues: window.textValues,
                buttonLabels: window.buttons.map(\.label),
                ownerName: window.ownerName
            ) else { continue }

            let answer = result.answerButtonIndex.flatMap { window.buttons[safe: $0]?.pressHandle }
            let decline = result.declineButtonIndex.flatMap { window.buttons[safe: $0]?.pressHandle }
            return SystemCallDetection(
                callerName: result.callerName,
                serviceName: result.serviceName,
                answerAction: pressAction(for: answer),
                declineAction: pressAction(for: decline)
            )
        }
        return nil
    }

    private func pressAction(
        for handle: SystemAccessibilityPressHandle?
    ) -> (@MainActor @Sendable () -> Void)? {
        guard let handle else { return nil }
        return { @MainActor @Sendable in
            handle.perform()
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
