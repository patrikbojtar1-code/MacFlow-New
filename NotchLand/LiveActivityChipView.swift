//
//  LiveActivityChipView.swift
//  NotchLand
//

import SwiftUI

enum LiveActivityChipMetrics {
    nonisolated static let flankWidth: CGFloat = NotchLayoutMetrics.bodySize(for: .small).width
    nonisolated static let compactSize = NotchLayoutMetrics.bodySize(for: .small)
    nonisolated static let mediumSize = NotchLayoutMetrics.bodySize(for: .medium)
    nonisolated static let largeSize = NotchLayoutMetrics.bodySize(for: .large)

    nonisolated static func size(for notchSize: NotchSize) -> CGSize {
        switch notchSize {
        case .small: compactSize
        case .medium: mediumSize
        case .large: largeSize
        }
    }
}

/// Shared compact activity surface. AirPods, messages, timers and downloads
/// use the same left/exclusion/right grid instead of independent pills.
struct LiveActivityChipView: View {
    let activity: LiveActivity

    @EnvironmentObject private var settings: NotchSettings
    @Environment(\.effectiveNotchSize) private var notchSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatesStatus = false

    private var exclusionWidth: CGFloat {
        NotchLayoutMetrics.exclusionWidth(
            hardwareWidth: CGFloat(settings.collapsedWidth),
            usesVirtualNotch: settings.virtualNotchEnabled
        )
    }

    var body: some View {
        NotchHardwareLayout(exclusionWidth: exclusionWidth, size: notchSize) {
            identityWing
        } right: {
            statusWing
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(NotchAmbientMotion.pulse(reduceMotion: reduceMotion)) {
                animatesStatus = true
            }
        }
        .animation(
            NotchAnimationProfile.animation(for: .compact, reduceMotion: reduceMotion),
            value: activity
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(activity.title)
        .accessibilityValue(activity.detail ?? "")
    }

    private var identityWing: some View {
        HStack(spacing: notchSize == .small ? 9 : 12) {
            accessoryIcon
                .frame(width: notchSize == .small ? 30 : 42, height: notchSize == .small ? 30 : 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.system(size: NotchLayoutMetrics.compactTitleSize, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if notchSize == .large, let detail = activity.detail {
                    Text(detail)
                        .font(.system(size: NotchLayoutMetrics.compactSubtitleSize, weight: .regular))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessoryIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: notchSize == .small ? 9 : 12, style: .continuous)
                .fill(Color.white.opacity(0.09))

            Image(systemName: symbol)
                .font(.system(size: notchSize == .small ? 16 : 22, weight: .medium))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: activity.presentationID)
        }
        .overlay {
            RoundedRectangle(cornerRadius: notchSize == .small ? 9 : 12, style: .continuous)
                .stroke(NotchTheme.subtleStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var statusWing: some View {
        switch activity.kind {
        case let .audioDevice(_, _, batteryPercent, phase):
            HStack(spacing: 8) {
                if notchSize == .small {
                    compactAccessoryStatus(phase: phase)
                } else {
                    Text(phase.displayName)
                        .font(.system(size: NotchLayoutMetrics.compactSubtitleSize, weight: .medium))
                        .foregroundStyle(statusTint(for: phase))
                        .contentTransition(.opacity)
                    compactAccessoryStatus(phase: phase)
                }

                if notchSize != .small, let batteryPercent {
                    Label("\(batteryPercent)%", systemImage: "battery.100percent")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                        .labelStyle(.titleAndIcon)
                }
            }
        case .message:
            detailStatus(symbol: "message.fill", tint: .green)
        case .timer:
            detailStatus(symbol: "timer", tint: .orange)
        case .download:
            if let progress = activity.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.green)
            } else {
                detailStatus(symbol: "arrow.down.circle.fill", tint: .green)
            }
        }
    }

    @ViewBuilder
    private func compactAccessoryStatus(phase: AudioAccessoryConnectionPhase) -> some View {
        switch phase {
        case .connecting, .disconnecting:
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: 2)
                Circle()
                    .trim(from: 0.08, to: 0.58)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(animatesStatus ? 360 : 0))
            }
            .frame(width: 20, height: 20)
            .animation(
                reduceMotion ? nil : .linear(duration: 0.8).repeatForever(autoreverses: false),
                value: animatesStatus
            )
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white, .green)
                .transition(.notchSuccess)
        case .disconnected:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76), .gray)
        case .lowBattery:
            Image(systemName: "battery.25percent")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    private func detailStatus(symbol: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            if notchSize != .small, let detail = activity.detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
            }
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var symbol: String {
        switch activity.kind {
        case let .audioDevice(_, model, _, _): model.symbolName
        case .message: "message.fill"
        case .timer: "timer"
        case .download: "arrow.down.circle.fill"
        }
    }

    private var tint: Color {
        switch activity.kind {
        case .audioDevice: .white
        case .message: .green
        case .timer: .orange
        case .download: .green
        }
    }

    private func statusTint(for phase: AudioAccessoryConnectionPhase) -> Color {
        switch phase {
        case .connected: .green
        case .lowBattery: .orange
        case .connecting, .disconnecting, .disconnected: NotchTheme.secondaryText
        }
    }
}

#if DEBUG
#Preview("Live Activity - AirPods") {
    NotchPreviewContainer {
        LiveActivityChipView(activity: LiveActivity(
            kind: .audioDevice(
                name: "AirPods Max",
                model: .airPodsMax,
                batteryPercent: 84,
                phase: .connected
            ),
            title: "AirPods Max",
            detail: "Connected",
            progress: nil
        ))
        .notchPreviewSurface(width: LiveActivityChipMetrics.compactSize.width, height: 50)
    }
}
#endif
