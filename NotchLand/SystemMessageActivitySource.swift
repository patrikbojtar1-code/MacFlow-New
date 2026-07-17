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

nonisolated struct SystemMessageFingerprintGate {
    private let missingSnapshotLimit: Int
    private(set) var lastFingerprint: String?
    private var missingSnapshots = 0

    init(missingSnapshotLimit: Int = 2) {
        self.missingSnapshotLimit = max(1, missingSnapshotLimit)
    }

    mutating func shouldPublish(_ fingerprint: String?) -> Bool {
        guard let fingerprint else {
            guard lastFingerprint != nil else { return false }
            missingSnapshots += 1
            if missingSnapshots >= missingSnapshotLimit {
                lastFingerprint = nil
                missingSnapshots = 0
            }
            return false
        }

        missingSnapshots = 0
        guard fingerprint != lastFingerprint else { return false }
        lastFingerprint = fingerprint
        return true
    }

    mutating func reset() {
        lastFingerprint = nil
        missingSnapshots = 0
    }
}

@MainActor
final class SystemMessageActivitySource {
    private let activities: LiveActivityController
    private let settings: NotchSettings
    private var fingerprintGate = SystemMessageFingerprintGate()
    private var dismissTask: Task<Void, Never>?

    init(activities: LiveActivityController, settings: NotchSettings) {
        self.activities = activities
        self.settings = settings
    }

    func start() {}

    func stop() {
        dismissTask?.cancel()
        dismissTask = nil
        fingerprintGate.reset()
    }

    func consume(
        snapshot: SystemAccessibilityActivitySnapshot,
        isAccessibilityTrusted: Bool
    ) {
        guard settings.systemCallDetectionEnabled, isAccessibilityTrusted else {
            registerMissingSnapshot()
            return
        }

        for window in snapshot.windows where window.ownerBundleIdentifier.contains("notificationcenter") {
            guard let result = SystemMessageWindowClassifier.classify(textValues: window.textValues) else { continue }
            let fingerprint = "\(result.sender)|\(result.body)"
            guard fingerprintGate.shouldPublish(fingerprint) else { return }
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
        registerMissingSnapshot()
    }

    private func registerMissingSnapshot() {
        _ = fingerprintGate.shouldPublish(nil)
    }
}
