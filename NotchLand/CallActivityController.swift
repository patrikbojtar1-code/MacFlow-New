//
//  CallActivityController.swift
//  NotchLand
//
//  Provider-ready call presentation state machine. macOS does not expose a
//  public CallKit observer for calls owned by FaceTime or other applications,
//  so integrations explicitly feed events and optional control callbacks here.
//

import AppKit
import Combine
import Foundation

struct CallPresentation: Identifiable, Equatable {
    enum Phase: Equatable {
        case incoming
        case connecting
        case active
        case ended(reason: String)
        case missed
    }

    let id: UUID
    var callerName: String
    var serviceName: String
    var phase: Phase
    var connectedAt: Date?
    var isMuted: Bool
    var supportsCallControl: Bool

    var initials: String {
        let parts = callerName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts)
        return value.isEmpty ? "?" : value.uppercased()
    }
}

extension CallPresentation: NotchActivityPresenting {
    var activityType: NotchActivityType { .call }
    var presentationID: String { id.uuidString }
    var primaryTitle: String { callerName }
    var secondaryTitle: String { serviceName }
}

@MainActor
final class CallActivityController: ObservableObject {
    typealias Action = @MainActor () -> Void

    @Published private(set) var current: CallPresentation?

    private var answerHandler: Action?
    private var declineHandler: Action?
    private var endHandler: Action?
    private var phaseTask: Task<Void, Never>?

    func receiveIncoming(
        callerName: String,
        serviceName: String,
        supportsCallControl: Bool = false,
        onAnswer: Action? = nil,
        onDecline: Action? = nil,
        onEnd: Action? = nil
    ) {
        phaseTask?.cancel()
        answerHandler = onAnswer
        declineHandler = onDecline
        endHandler = onEnd
        current = CallPresentation(
            id: UUID(),
            callerName: normalized(callerName, fallback: "Unknown Caller"),
            serviceName: normalized(serviceName, fallback: "Incoming Call"),
            phase: .incoming,
            connectedAt: nil,
            isMuted: false,
            supportsCallControl: supportsCallControl
        )
        NotchHaptics.perform(.confirmation)
        scheduleMissedCallTimeout()
    }

    func answer() {
        guard var call = current,
              call.phase == .incoming,
              call.supportsCallControl else { return }
        phaseTask?.cancel()
        answerHandler?()
        call.phase = .connecting
        current = call
        NotchHaptics.perform(.confirmation)

        let id = call.id
        phaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(620))
            guard let self, !Task.isCancelled, var call = current, call.id == id else { return }
            call.phase = .active
            call.connectedAt = .now
            current = call
        }
    }

    func decline() {
        guard current?.phase == .incoming else { return }
        declineHandler?()
        finish(reason: "Declined")
    }

    func end() {
        guard let phase = current?.phase,
              phase == .active || phase == .connecting else { return }
        endHandler?()
        finish(reason: "Call Ended")
    }

    func toggleMute() {
        guard var call = current, call.phase == .active else { return }
        call.isMuted.toggle()
        current = call
        NotchHaptics.perform(.navigation)
    }

    func openCallingApp() {
        guard let call = current else { return }
        let bundleIdentifiers = [
            "facetime": "com.apple.FaceTime",
            "continuity": "com.apple.FaceTime",
            "microsoft teams": "com.microsoft.teams2",
            "zoom": "us.zoom.xos",
            "slack": "com.tinyspeck.slackmacgap",
        ]
        let key = call.serviceName.lowercased()
        let matchingBundle = bundleIdentifiers.first { key.contains($0.key) }?.value
        guard let matchingBundle,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: matchingBundle) else {
            NotchHaptics.perform(.rejection)
            return
        }
        Task {
            try? await NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
        NotchHaptics.perform(.navigation)
    }

    func dismiss() {
        phaseTask?.cancel()
        phaseTask = nil
        current = nil
        clearHandlers()
    }

    func systemCallBannerDidDisappear(id: UUID) {
        guard let call = current, call.id == id, call.phase == .incoming else { return }
        finish(reason: "Call Dismissed")
    }

    func showDesignPreview() {
        receiveIncoming(
            callerName: "Anna Nováková",
            serviceName: "FaceTime Video",
            supportsCallControl: true
        )
    }

    private func finish(reason: String) {
        phaseTask?.cancel()
        guard var call = current else { return }
        call.phase = .ended(reason: reason)
        current = call
        NotchHaptics.perform(.navigation)
        scheduleDismiss(after: .seconds(2))
    }

    private func scheduleMissedCallTimeout() {
        guard let id = current?.id else { return }
        phaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled, var call = current,
                  call.id == id, call.phase == .incoming else { return }
            call.phase = .missed
            current = call
            NotchHaptics.perform(.rejection)
            scheduleDismiss(after: .seconds(3))
        }
    }

    private func scheduleDismiss(after delay: Duration) {
        let id = current?.id
        phaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, current?.id == id else { return }
            dismiss()
        }
    }

    private func clearHandlers() {
        answerHandler = nil
        declineHandler = nil
        endHandler = nil
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
