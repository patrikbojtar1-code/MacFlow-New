//
//  AppMotion.swift
//  MacFlow
//
//  Small, semantic motion vocabulary for the MacFlow application shell.
//

import AppKit
import SwiftUI

nonisolated enum AppMotion {
    enum Duration {
        static let instant: TimeInterval = 0.10
        static let quick: TimeInterval = 0.16
        static let standard: TimeInterval = 0.22
        static let emphasized: TimeInterval = 0.34
    }

    static func stateChange(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? Duration.instant : Duration.standard)
    }

    static func insertion(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? Duration.instant : Duration.standard)
    }

    static func removal(reduceMotion: Bool) -> Animation {
        .easeIn(duration: reduceMotion ? Duration.instant : Duration.quick)
    }

    static func interaction(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: Duration.instant)
            : .spring(response: Duration.standard, dampingFraction: 0.92, blendDuration: 0)
    }

    static func emphasized(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: Duration.instant)
            : .spring(response: Duration.emphasized, dampingFraction: 0.94, blendDuration: 0)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity
        )
    }

    static func directionalTransition(reduceMotion: Bool, forward: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 8 : -8)),
            removal: .opacity
        )
    }
}

// MARK: - Debug motion instrumentation

enum MotionDebug {
    @MainActor
    static func record(
        name: String,
        surface: String,
        duration: TimeInterval,
        state: String,
        reason: String
    ) {
        #if NOTCHLAND_ENABLE_DEBUG_UI
        MotionDebugStore.shared.record(
            name: name,
            surface: surface,
            duration: duration,
            state: state,
            reason: reason
        )
        #endif
    }
}

#if NOTCHLAND_ENABLE_DEBUG_UI

enum MotionDebugPhase: String, Equatable {
    case active
    case completed
    case interrupted
}

struct MotionDebugEvent: Identifiable, Equatable {
    let id: UUID
    let name: String
    let surface: String
    let duration: TimeInterval
    let state: String
    let reason: String
    let startedAt: Date
    var phase: MotionDebugPhase
    var redrawCount: Int
}

/// DEBUG-only event recorder. Production animation code does not observe this
/// object, so opening the debugger cannot invalidate or slow the notch tree.
@MainActor
final class MotionDebugStore: ObservableObject {
    static let shared = MotionDebugStore()

    @Published private(set) var events: [MotionDebugEvent] = []
    @Published private(set) var renderCounts: [String: Int] = [:]
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { interruptActiveEvents() }
        }
    }

    private static let enabledKey = "debug.motionDebugger.enabled"
    private static let eventLimit = 80
    private let defaults: UserDefaults
    private var completionTasks: [UUID: Task<Void, Never>] = [:]

    init(defaults: UserDefaults = .standard, enabled: Bool? = nil) {
        self.defaults = defaults
        isEnabled = enabled ?? defaults.bool(forKey: Self.enabledKey)
    }

    var activeEvents: [MotionDebugEvent] {
        events.filter { $0.phase == .active }
    }

    func record(
        name: String,
        surface: String,
        duration: TimeInterval,
        state: String,
        reason: String
    ) {
        guard isEnabled else { return }

        interruptMatchingEvent(name: name, surface: surface)
        let id = UUID()
        let event = MotionDebugEvent(
            id: id,
            name: name,
            surface: surface,
            duration: max(0, duration),
            state: state,
            reason: reason,
            startedAt: .now,
            phase: .active,
            redrawCount: 0
        )
        events.insert(event, at: 0)
        if events.count > Self.eventLimit {
            events.removeLast(events.count - Self.eventLimit)
        }

        completionTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, duration)))
            guard let self, !Task.isCancelled else { return }
            self.finish(id: id)
        }
    }

    func markRender(surface: String) {
        guard isEnabled else { return }
        renderCounts[surface, default: 0] += 1
        for index in events.indices where events[index].surface == surface && events[index].phase == .active {
            events[index].redrawCount += 1
        }
    }

    func clear() {
        completionTasks.values.forEach { $0.cancel() }
        completionTasks.removeAll()
        events.removeAll()
        renderCounts.removeAll()
    }

    private func finish(id: UUID) {
        completionTasks[id] = nil
        guard let index = events.firstIndex(where: { $0.id == id }),
              events[index].phase == .active else { return }
        events[index].phase = .completed
    }

    private func interruptMatchingEvent(name: String, surface: String) {
        guard let index = events.firstIndex(where: {
            $0.name == name && $0.surface == surface && $0.phase == .active
        }) else { return }
        let id = events[index].id
        completionTasks[id]?.cancel()
        completionTasks[id] = nil
        events[index].phase = .interrupted
    }

    private func interruptActiveEvents() {
        completionTasks.values.forEach { $0.cancel() }
        completionTasks.removeAll()
        for index in events.indices where events[index].phase == .active {
            events[index].phase = .interrupted
        }
    }
}

private struct MotionRenderProbe: NSViewRepresentable {
    let surface: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            MotionDebugStore.shared.markRender(surface: surface)
        }
    }
}

#endif

extension View {
    @ViewBuilder
    func motionDebugProbe(_ surface: String) -> some View {
        #if NOTCHLAND_ENABLE_DEBUG_UI
        background(MotionRenderProbe(surface: surface))
        #else
        self
        #endif
    }
}
