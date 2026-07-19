//
//  CallOverlayView.swift
//  NotchLand
//

import SwiftUI

enum CallOverlayMetrics {
    nonisolated static let incomingSize = NotchLayoutMetrics.bodySize(for: .small)
    // Every compact call phase keeps the same shell footprint. Only content
    // changes, so accepting or dismissing never shifts the notch sideways.
    nonisolated static let activeSize = NotchLayoutMetrics.bodySize(for: .small)
    nonisolated static let endedSize = NotchLayoutMetrics.bodySize(for: .small)
    nonisolated static let mediumSize = NotchLayoutMetrics.bodySize(for: .medium)
    nonisolated static let largeSize = NotchLayoutMetrics.bodySize(for: .large)

    nonisolated static func size(
        for presentation: CallPresentation,
        notchSize: NotchSize = .small
    ) -> CGSize {
        if notchSize == .large { return largeSize }
        if notchSize == .medium { return mediumSize }
        return switch presentation.phase {
        case .incoming, .connecting: incomingSize
        case .active: activeSize
        case .ended, .missed: endedSize
        }
    }
}

/// One call renderer for incoming, active and result phases. Content can only
/// occupy the left and right wings; `NotchHardwareLayout` owns the black camera
/// exclusion region between them.
struct CallOverlayView: View {
    let presentation: CallPresentation

    @EnvironmentObject private var calls: CallActivityController
    @EnvironmentObject private var settings: NotchSettings
    @Environment(\.effectiveNotchSize) private var notchSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRinging = false


    private var exclusionWidth: CGFloat {
        NotchLayoutMetrics.exclusionWidth(
            hardwareWidth: CGFloat(settings.collapsedWidth),
            usesVirtualNotch: settings.virtualNotchEnabled
        )
    }

    var body: some View {
        NotchHardwareLayout(exclusionWidth: exclusionWidth, size: notchSize) {
            leftWing
                .id("left-\(phaseIdentity)")
                .transition(phaseTransition(edge: .leading))
        } right: {
            rightWing
                .id("right-\(phaseIdentity)")
                .transition(phaseTransition(edge: .trailing))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            NotchAnimationProfile.animation(for: .compact, reduceMotion: reduceMotion),
            value: phaseIdentity
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(NotchAmbientMotion.ringing(reduceMotion: reduceMotion)) {
                isRinging = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var leftWing: some View {
        switch presentation.phase {
        case .incoming:
            identityWing(status: presentation.serviceName, showsPulse: true)
        case .connecting:
            identityWing(status: "Connecting…", showsPulse: false)
        case .active:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                identityWing(status: activeDuration(at: context.date), showsPulse: false)
            }
        case .ended:
            resultIdentity(symbol: "phone.down.fill")
        case .missed:
            resultIdentity(symbol: "phone.badge.xmark.fill")
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        switch presentation.phase {
        case .incoming:
            HStack(spacing: notchSize == .small ? 4 : 12) {
                if presentation.supportsCallControl {
                    actionButton(
                        symbol: "phone.down.fill",
                        title: "Decline",
                        color: .red,
                        action: calls.decline
                    )
                    actionButton(
                        symbol: presentation.serviceName.localizedCaseInsensitiveContains("video")
                            ? "video.fill" : "phone.fill",
                        title: "Answer",
                        color: .green,
                        action: calls.answer
                    )
                } else {
                    actionButton(symbol: "xmark", title: "Dismiss", color: .gray, action: calls.dismiss)
                    actionButton(
                        symbol: "arrow.up.forward.app.fill",
                        title: "Open",
                        color: .blue,
                        action: calls.openCallingApp
                    )
                }
            }
        case .connecting:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                actionButton(symbol: "phone.down.fill", title: "End", color: .red, action: calls.end)
            }
        case .active:
            HStack(spacing: notchSize == .small ? 4 : 12) {
                actionButton(
                    symbol: presentation.isMuted ? "mic.slash.fill" : "mic.fill",
                    title: presentation.isMuted ? "Unmute" : "Mute",
                    color: presentation.isMuted ? .orange : .gray,
                    action: calls.toggleMute
                )
                actionButton(symbol: "phone.down.fill", title: "End", color: .red, action: calls.end)
            }
        case let .ended(reason):
            resultLabel(reason, tint: .secondary)
        case .missed:
            resultLabel("Missed call", tint: .red)
        }
    }

    private func identityWing(status: String, showsPulse: Bool) -> some View {
        HStack(spacing: notchSize == .small ? 9 : 12) {
            avatar(size: notchSize == .small ? 30 : 42, showsPulse: showsPulse)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.callerName)
                    .font(.system(size: NotchLayoutMetrics.compactTitleSize, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                if notchSize == .large {
                    Text(status)
                        .font(.system(size: NotchLayoutMetrics.compactSubtitleSize, weight: .regular))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func resultIdentity(symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 28, height: 28)
                .background(NotchTheme.interactiveSurface, in: Circle())
            Text(presentation.callerName)
                .font(.system(size: NotchLayoutMetrics.compactTitleSize, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1)
        }
    }

    private func resultLabel(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: NotchLayoutMetrics.compactSubtitleSize, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .transition(.opacity)
    }

    private func avatar(size: CGFloat, showsPulse: Bool) -> some View {
        ZStack {
            if showsPulse {
                Circle()
                    .stroke(.green.opacity(0.30), lineWidth: 1)
                    .scaleEffect(isRinging ? 1.28 : 0.96)
                    .opacity(isRinging ? 0 : 0.62)
            }
            Circle()
                .fill(Color.white.opacity(0.13))
                .overlay {
                    Text(presentation.initials)
                        .font(.system(size: size * 0.31, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
        .frame(width: size, height: size)
    }

    private func actionButton(
        symbol: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        let dimension: CGFloat = notchSize == .small ? 26 : 36
        return Button {
            NotchHaptics.perform(.navigation)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: notchSize == .small ? 11 : 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: dimension, height: dimension)
                .background(color.opacity(0.94), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private func activeDuration(at date: Date) -> String {
        guard let connectedAt = presentation.connectedAt else { return "Connected" }
        let elapsed = max(0, Int(date.timeIntervalSince(connectedAt)))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private var phaseIdentity: String {
        switch presentation.phase {
        case .incoming: "incoming"
        case .connecting: "connecting"
        case .active: "active"
        case .ended: "ended"
        case .missed: "missed"
        }
    }

    private func phaseTransition(edge: Edge) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: edge == .leading ? -5 : 5)),
            removal: .opacity
        )
    }
}
