import AppKit
import ApplicationServices
import Foundation

nonisolated enum SystemMessageWindowClassifier {
    struct Result: Equatable, Sendable {
        let sender: String
        let body: String
    }

    private static let markers = ["messages", "imessage", "sms", "zpravy"]
    private static let ignored = ["notification center", "notificationcenter", "close", "reply", "odpovedet"]

    static func classify(textValues: [String]) -> Result? {
        let normalized = textValues.map { value in
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard normalized.contains(where: { value in markers.contains(where: value.contains) }) else { return nil }
        let content = zip(textValues, normalized).compactMap { original, folded -> String? in
            guard !markers.contains(where: { folded == $0 }),
                  !ignored.contains(where: folded.contains),
                  !folded.isEmpty,
                  folded.count <= 240 else { return nil }
            return original.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let sender = content.first else { return nil }
        return Result(sender: sender, body: content.dropFirst().first ?? "New message")
    }
}

@MainActor
final class SystemMessageActivitySource {
    private let activities: LiveActivityController
    private let settings: NotchSettings
    private var timer: Timer?
    private var lastFingerprint: String?
    private var dismissTask: Task<Void, Never>?

    init(activities: LiveActivityController, settings: NotchSettings) {
        self.activities = activities
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.65, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        dismissTask?.cancel()
    }

    private func poll() {
        guard settings.systemCallDetectionEnabled, AXIsProcessTrusted() else { return }
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier ?? "").lowercased().contains("notificationcenter")
        }) else { return }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        for window in elements(kAXWindowsAttribute, from: app) {
            let values = readableText(in: window)
            guard let result = SystemMessageWindowClassifier.classify(textValues: values) else { continue }
            let fingerprint = "\(result.sender)|\(result.body)"
            guard fingerprint != lastFingerprint else { return }
            lastFingerprint = fingerprint
            let activity = LiveActivity(
                kind: .message(sender: result.sender),
                title: result.sender,
                detail: result.body,
                progress: nil
            )
            activities.post(activity)
            dismissTask?.cancel()
            dismissTask = Task { @MainActor [weak activities] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                activities?.end(activity.id)
            }
            return
        }
    }

    private func readableText(in root: AXUIElement) -> [String] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var result: [String] = []
        var index = 0
        while index < queue.count, index < 220 {
            let (element, depth) = queue[index]
            index += 1
            if let role = string(kAXRoleAttribute, from: element),
               role == kAXStaticTextRole as String || role == kAXHeadingRole as String {
                for attribute in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                    if let value = string(attribute, from: element), !result.contains(value) { result.append(value) }
                }
            }
            if depth < 8 { queue.append(contentsOf: elements(kAXChildrenAttribute, from: element).map { ($0, depth + 1) }) }
        }
        return result
    }

    private func string(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func elements(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
