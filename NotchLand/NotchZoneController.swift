//
//  NotchZoneController.swift
//  NotchLand
//
//  Intent-aware hover state and physical-notch-safe hit testing.
//

import Combine
import Foundation

nonisolated enum NotchZone: Equatable, Sendable {
    case timeline
    case center
    case shortcuts
}

nonisolated enum NotchZoneLayout {
    static let hoverSideExpansion: CGFloat = 110

    static func zone(at x: CGFloat, totalWidth: CGFloat, hardwareWidth: CGFloat) -> NotchZone {
        let safeTotal = max(0, totalWidth)
        let safeHardware = min(max(0, hardwareWidth), safeTotal)
        let sideWidth = max(0, (safeTotal - safeHardware) / 2)
        if x < sideWidth { return .timeline }
        if x > safeTotal - sideWidth { return .shortcuts }
        return .center
    }

    static func sideWidth(totalWidth: CGFloat, hardwareWidth: CGFloat) -> CGFloat {
        max(0, (totalWidth - min(max(0, hardwareWidth), max(0, totalWidth))) / 2)
    }
}

@MainActor
final class NotchZoneController: ObservableObject {
    enum Phase: Equatable {
        case hidden
        case armed
        case visible
    }

    @Published private(set) var phase: Phase = .hidden

    private let revealDelay: Duration
    private var revealTask: Task<Void, Never>?
    private var isHovering = false
    private var isEligible = false

    init(revealDelay: Duration = .milliseconds(145)) {
        self.revealDelay = revealDelay
    }

    var isVisible: Bool { phase == .visible }

    func update(isHovering: Bool, isEligible: Bool, reduceMotion: Bool) {
        self.isHovering = isHovering
        self.isEligible = isEligible
        revealTask?.cancel()

        guard isHovering, isEligible else {
            phase = .hidden
            return
        }

        phase = .armed
        revealTask = Task { [weak self] in
            guard let self else { return }
            if !reduceMotion {
                try? await Task.sleep(for: revealDelay)
            }
            guard !Task.isCancelled, self.isHovering, self.isEligible else { return }
            phase = .visible
        }
    }

    func hide() {
        revealTask?.cancel()
        revealTask = nil
        isEligible = false
        phase = .hidden
    }
}
