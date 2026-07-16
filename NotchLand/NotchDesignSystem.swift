//
//  NotchDesignSystem.swift
//  NotchLand
//
//  Shared interaction tokens keep every feature feeling like part of the same
//  physical surface instead of a collection of independently tuned views.
//

import AppKit
import SwiftUI

// MARK: - Unified notch presentation foundation

/// User-facing density. The selected density changes presentation, not the
/// underlying activity data or controller ownership.
nonisolated enum NotchSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

nonisolated enum NotchPresentationState: String, Equatable, Sendable {
    case idle
    case hover
    case compact
    case medium
    case expanded
}

nonisolated enum NotchActivityType: String, CaseIterable, Identifiable, Sendable {
    case media
    case call
    case bluetooth
    case calendar
    case clipboard
    case shortcuts
    case fileShelf
    case timer
    case reminder
    case systemStatus

    var id: String { rawValue }
}

/// Common identity consumed by notch activity renderers. Feature controllers
/// remain responsible for business logic and adapt their current value to this
/// small presentation surface.
protocol NotchActivityPresenting {
    var activityType: NotchActivityType { get }
    var presentationID: String { get }
    var primaryTitle: String { get }
    var secondaryTitle: String { get }
}

nonisolated enum NotchLayoutMetrics {
    static let grid: CGFloat = 8
    static let minimumHardwareExclusionWidth: CGFloat = 176
    static let maximumHardwareExclusionWidth: CGFloat = 238
    static let defaultVirtualExclusionWidth: CGFloat = 184

    static let compactHorizontalPadding: CGFloat = 16
    static let mediumHorizontalPadding: CGFloat = 22
    static let largeHorizontalPadding: CGFloat = 28

    static let compactBottomRadius: CGFloat = 22
    static let mediumBottomRadius: CGFloat = 28
    static let largeBottomRadius: CGFloat = 34

    static let compactTitleSize: CGFloat = 14
    static let compactSubtitleSize: CGFloat = 11
    static let expandedTitleSize: CGFloat = 26
    static let bodySize: CGFloat = 13

    static let hoverWidthExpansion: CGFloat = 24
    static let hoverHeightExpansion: CGFloat = 3

    static func bodySize(for size: NotchSize) -> CGSize {
        switch size {
        case .small: CGSize(width: 520, height: 50)
        case .medium: CGSize(width: 700, height: 78)
        case .large: CGSize(width: 760, height: 90)
        }
    }

    static func horizontalPadding(for size: NotchSize) -> CGFloat {
        switch size {
        case .small: compactHorizontalPadding
        case .medium: mediumHorizontalPadding
        case .large: largeHorizontalPadding
        }
    }

    static func bottomRadius(for size: NotchSize) -> CGFloat {
        switch size {
        case .small: compactBottomRadius
        case .medium: mediumBottomRadius
        case .large: largeBottomRadius
        }
    }

    static func exclusionWidth(hardwareWidth: CGFloat, usesVirtualNotch: Bool) -> CGFloat {
        let requested = hardwareWidth > 0
            ? hardwareWidth
            : (usesVirtualNotch ? defaultVirtualExclusionWidth : 0)
        guard requested > 0 else { return 0 }
        return min(max(requested, minimumHardwareExclusionWidth), maximumHardwareExclusionWidth)
    }
}

enum NotchTheme {
    static let surface = Color.black.opacity(0.93)
    static let materialOverlay = Color.black.opacity(0.62)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.58)
    static let subtleStroke = Color.white.opacity(0.10)
    static let increasedContrastStroke = Color.white.opacity(0.28)
    static let shadow = Color.black.opacity(0.42)
    static let interactiveSurface = Color.white.opacity(0.10)
}

nonisolated enum NotchAnimationProfile {
    static let hoverDuration: TimeInterval = 0.14
    static let widthDuration: TimeInterval = 0.17
    static let heightDuration: TimeInterval = 0.21
    static let contentDuration: TimeInterval = 0.19
    static let expandDuration: TimeInterval = 0.26
    static let collapseDuration: TimeInterval = 0.22
    static let dampingFraction = 0.92

    static func spring(duration: TimeInterval, reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: min(duration, 0.10))
            : .spring(response: duration, dampingFraction: dampingFraction, blendDuration: 0)
    }

    static func animation(for state: NotchPresentationState, reduceMotion: Bool) -> Animation {
        switch state {
        case .hover:
            spring(duration: hoverDuration, reduceMotion: reduceMotion)
        case .medium:
            spring(duration: heightDuration, reduceMotion: reduceMotion)
        case .expanded:
            spring(duration: expandDuration, reduceMotion: reduceMotion)
        case .idle, .compact:
            spring(duration: collapseDuration, reduceMotion: reduceMotion)
        }
    }
}

/// Mandatory three-region layout for every compact and medium activity. The
/// center is deliberately rendered as empty black space and is hidden from
/// accessibility and hit testing, so no feature can accidentally occupy the
/// camera housing.
struct NotchHardwareLayout<Left: View, Right: View>: View {
    let exclusionWidth: CGFloat
    let size: NotchSize
    let left: Left
    let right: Right

    init(
        exclusionWidth: CGFloat,
        size: NotchSize,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.exclusionWidth = exclusionWidth
        self.size = size
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(spacing: 0) {
            left
                .frame(maxWidth: .infinity, alignment: .leading)

            Color.black
                .frame(width: exclusionWidth)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            right
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, NotchLayoutMetrics.horizontalPadding(for: size))
    }
}

nonisolated enum NotchMotionRole: String, CaseIterable, Sendable {
    case hover
    case zoneReveal
    case selection
    case contentEnter
    case containerExpand
    case interruption
    case success
    case contentReturn
    case dismiss
}

nonisolated struct NotchMotionMeasurement: Equatable, Sendable {
    enum Curve: Equatable, Sendable {
        case spring
        case easeOut
        case easeInOut
    }

    let curve: Curve
    let duration: TimeInterval
    let dampingFraction: Double?
    let delay: TimeInterval

    init(
        curve: Curve,
        duration: TimeInterval,
        dampingFraction: Double? = nil,
        delay: TimeInterval = 0
    ) {
        self.curve = curve
        self.duration = duration
        self.dampingFraction = dampingFraction
        self.delay = delay
    }

    var animation: Animation {
        let base: Animation
        switch curve {
        case .spring:
            base = .spring(
                response: duration,
                dampingFraction: dampingFraction ?? 0.86,
                blendDuration: 0
            )
        case .easeOut:
            base = .easeOut(duration: duration)
        case .easeInOut:
            base = .easeInOut(duration: duration)
        }
        return delay > 0 ? base.delay(delay) : base
    }
}

/// One measured motion graph for the whole product. Roles describe intent,
/// not individual screens, so energy carries from a container morph into its
/// content rather than restarting with unrelated spring parameters.
nonisolated enum NotchMotionGraph {
    static let reduced = NotchMotionMeasurement(curve: .easeOut, duration: 0.10)

    static let measurements: [NotchMotionRole: NotchMotionMeasurement] = [
        .hover: .init(curve: .spring, duration: 0.28, dampingFraction: 0.88),
        .zoneReveal: .init(curve: .spring, duration: 0.26, dampingFraction: 0.86),
        .selection: .init(curve: .spring, duration: 0.24, dampingFraction: 0.88),
        .contentEnter: .init(curve: .spring, duration: 0.34, dampingFraction: 0.88, delay: 0.045),
        .containerExpand: .init(curve: .spring, duration: 0.44, dampingFraction: 0.84),
        .interruption: .init(curve: .spring, duration: 0.36, dampingFraction: 0.90),
        .success: .init(curve: .spring, duration: 0.42, dampingFraction: 0.70),
        .contentReturn: .init(curve: .spring, duration: 0.50, dampingFraction: 0.90),
        .dismiss: .init(curve: .easeInOut, duration: 0.22),
    ]

    /// The short compression phase gives an interrupted surface somewhere to
    /// move from. A one-frame handoff prevents both branches rendering at full
    /// visual weight during the shared-element identity swap.
    static let compressDuration: TimeInterval = 0.15
    static let handoffDelay: TimeInterval = 1.0 / 60.0
    static let openSettleDuration: TimeInterval = 0.36
    static let returnSettleDuration: TimeInterval = 0.52
    static let contentScaleFrom: CGFloat = 0.78
    static let contentOffsetFrom: CGFloat = -8
    static let containerBlurRadius: CGFloat = 10
    static let contentBlurRadius: CGFloat = 8

    static func measurement(for role: NotchMotionRole) -> NotchMotionMeasurement {
        measurements[role] ?? reduced
    }

    static func animation(for role: NotchMotionRole, reduceMotion: Bool = false) -> Animation {
        (reduceMotion ? reduced : measurement(for: role)).animation
    }

    static func compressionAnimation(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? reduced.animation : .easeOut(duration: compressDuration)
    }
}

enum NotchMotion {
    nonisolated static let expand = NotchMotionGraph.animation(for: .containerExpand)
    nonisolated static let hover = NotchMotionGraph.animation(for: .hover)
    nonisolated static let zoneReveal = NotchMotionGraph.animation(for: .zoneReveal)
    nonisolated static let contentOpen = NotchMotionGraph.animation(for: .contentEnter)
    nonisolated static let contentReturn = NotchMotionGraph.animation(for: .contentReturn)
    nonisolated static let selection = NotchMotionGraph.animation(for: .selection)
    nonisolated static let interruption = NotchMotionGraph.animation(for: .interruption)
    nonisolated static let success = NotchMotionGraph.animation(for: .success)
    nonisolated static let dismiss = NotchMotionGraph.animation(for: .dismiss)
    nonisolated static let dropTarget = NotchMotionGraph.animation(for: .interruption)

    nonisolated static let contentOpeningScale = NotchMotionGraph.contentScaleFrom
    nonisolated static let contentOpeningBlurRadius = NotchMotionGraph.contentBlurRadius
    nonisolated static let containerBlurRadius = NotchMotionGraph.containerBlurRadius
    nonisolated static let contentBlurRadius = NotchMotionGraph.contentBlurRadius
}

/// Repeating effects have a separate cadence from state transitions. They
/// never own layout and can be disabled without changing functionality.
nonisolated enum NotchAmbientMotion {
    static let pulseDuration: TimeInterval = 0.72
    static let ringingDuration: TimeInterval = 0.78
    static let orbitDuration: TimeInterval = 1.10
    static let dropOrbitDuration: TimeInterval = 1.70
    static let shimmerDuration: TimeInterval = 1.50
    static let celebrationDuration: TimeInterval = 1.25
    static let showcaseDuration: TimeInterval = 1.20
    static let spinnerDuration: TimeInterval = 0.80

    static func pulse(reduceMotion: Bool = false) -> Animation {
        reduceMotion
            ? NotchMotionGraph.reduced.animation
            : .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)
    }

    static func orbit(delay: TimeInterval = 0, reduceMotion: Bool = false) -> Animation {
        reduceMotion
            ? NotchMotionGraph.reduced.animation
            : .easeOut(duration: orbitDuration).repeatForever(autoreverses: false).delay(delay)
    }

    static func spinner(reduceMotion: Bool = false) -> Animation {
        reduceMotion
            ? NotchMotionGraph.reduced.animation
            : .linear(duration: spinnerDuration).repeatForever(autoreverses: false)
    }

    static func ringing(reduceMotion: Bool = false) -> Animation {
        reduceMotion
            ? NotchMotionGraph.reduced.animation
            : .easeInOut(duration: ringingDuration).repeatForever(autoreverses: true)
    }

    static func shimmer(reduceMotion: Bool = false) -> Animation {
        reduceMotion
            ? NotchMotionGraph.reduced.animation
            : .easeOut(duration: shimmerDuration).repeatForever(autoreverses: false)
    }

    static func celebration(reduceMotion: Bool = false) -> Animation {
        reduceMotion
            ? NotchMotionGraph.reduced.animation
            : .easeOut(duration: celebrationDuration).repeatForever(autoreverses: false)
    }

    static func showcase(reduceMotion: Bool = false) -> Animation {
        reduceMotion
            ? NotchMotionGraph.reduced.animation
            : .easeInOut(duration: showcaseDuration).repeatForever(autoreverses: true)
    }

    static func dropOrbit(delay: TimeInterval = 0, reduceMotion: Bool = false) -> Animation {
        reduceMotion
            ? NotchMotionGraph.reduced.animation
            : .easeOut(duration: dropOrbitDuration).repeatForever(autoreverses: false).delay(delay)
    }
}

extension AnyTransition {
    /// Default handoff between feature sections. The outgoing view yields
    /// quickly while the incoming view inherits the container's vertical
    /// direction and spring energy.
    static var notchSection: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: NotchMotionGraph.contentScaleFrom, anchor: .top))
                .combined(with: .offset(y: NotchMotionGraph.contentOffsetFrom))
                .animation(NotchMotionGraph.animation(for: .contentEnter)),
            removal: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .top))
                .animation(NotchMotionGraph.animation(for: .dismiss))
        )
    }

    /// A restrained overshoot for confirmations and completed operations.
    static var notchSuccess: AnyTransition {
        .scale(scale: NotchMotionGraph.contentScaleFrom)
            .combined(with: .opacity)
            .animation(NotchMotionGraph.animation(for: .success))
    }
}

@MainActor
enum NotchHaptics {
    enum Feedback {
        case navigation
        case confirmation
        case rejection
    }

    static func perform(_ feedback: Feedback) {
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        let performanceTime: NSHapticFeedbackManager.PerformanceTime

        switch feedback {
        case .navigation:
            pattern = .alignment
            performanceTime = .now
        case .confirmation:
            pattern = .levelChange
            performanceTime = .now
        case .rejection:
            NSSound.beep()
            return
        }

        NSHapticFeedbackManager.defaultPerformer.perform(
            pattern,
            performanceTime: performanceTime
        )
    }
}
