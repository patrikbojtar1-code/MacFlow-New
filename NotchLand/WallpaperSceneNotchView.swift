//
//  WallpaperSceneNotchView.swift
//  NotchLand
//
//  Hardware-safe compact control and drag target for NotchLand Scenes.
//

import AppKit
import SwiftUI

enum WallpaperSceneNotchMetrics {
    nonisolated static let compactSize = NotchLayoutMetrics.bodySize(for: .small)
    nonisolated static let mediumSize = NotchLayoutMetrics.bodySize(for: .medium)
    nonisolated static let largeSize = NotchLayoutMetrics.bodySize(for: .large)
    nonisolated static let dropSize = CGSize(width: 360, height: 138)

    nonisolated static func size(for notchSize: NotchSize, isHovering: Bool = false) -> CGSize {
        let base = switch notchSize {
        case .small: compactSize
        case .medium: mediumSize
        case .large: largeSize
        }
        guard isHovering else { return base }
        return CGSize(
            width: base.width + NotchLayoutMetrics.hoverWidthExpansion,
            height: base.height + NotchLayoutMetrics.hoverHeightExpansion
        )
    }
}

struct WallpaperSceneCompactView: View {
    let scene: WallpaperScene
    let isHovering: Bool

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var controller: WallpaperSceneController
    @Environment(\.effectiveNotchSize) private var notchSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            controlWing
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(AppMotion.interaction(reduceMotion: reduceMotion), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wallpaper scene, \(scene.title)")
        .accessibilityValue(accessibilityValue)
    }

    private var identityWing: some View {
        HStack(spacing: notchSize == .small ? 9 : 12) {
            scenePreview
                .frame(
                    width: notchSize == .small ? 28 : 44,
                    height: notchSize == .small ? 28 : 44
                )
                .clipShape(RoundedRectangle(cornerRadius: notchSize == .small ? 9 : 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(scene.title)
                    .font(.system(size: NotchLayoutMetrics.compactTitleSize, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)

                if notchSize == .large || isHovering {
                    Text(
                        controller.suspensionDetail
                            ?? controller.automationReason?.title
                            ?? "\(scene.kind.displayName) · \(controller.performance.effectiveProfile.title)"
                    )
                        .font(.system(size: NotchLayoutMetrics.compactSubtitleSize))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .transition(.opacity.combined(with: .offset(x: -4)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scenePreview: some View {
        WallpaperPreviewImage(
            scene: scene,
            url: controller.library.previewURL(for: scene),
            scalingMode: .fill
        )
        .scaleEffect(isHovering && !reduceMotion ? 1.035 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: notchSize == .small ? 9 : 12, style: .continuous)
                .stroke(NotchTheme.subtleStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var controlWing: some View {
        if scene.kind == .video {
            HStack(spacing: notchSize == .small ? 9 : 12) {
                if controller.isSuspendedBySystem {
                    Image(systemName: controller.isFullscreenApplicationActive ? "rectangle.inset.filled" : "leaf.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    SceneMotionBars(
                        isActive: !controller.isPaused,
                        isEmphasized: isHovering
                    )
                }

                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: notchSize == .small ? 17 : 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: notchSize == .small ? 30 : 38, height: notchSize == .small ? 30 : 38)
                    .background(.white.opacity(0.08), in: Circle())
                    .background(isHovering ? .white.opacity(0.06) : .clear, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "photo.fill")
                    .foregroundStyle(.white.opacity(0.72))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .offset(x: isHovering && !reduceMotion ? 2 : 0)
            }
            .opacity(isHovering ? 1 : 0.72)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var accessibilityValue: String {
        if let suspensionDetail = controller.suspensionDetail { return suspensionDetail }
        if scene.kind == .image { return "Still image scene" }
        return controller.isPaused ? "Paused" : "Playing"
    }
}

private struct SceneMotionBars: View {
    let isActive: Bool
    let isEmphasized: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: AppMotion.FrameInterval.lowFrequency, paused: !isActive || reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<5, id: \.self) { index in
                    let amplitude = (sin(phase * 5.2 + Double(index) * 1.17) + 1) / 2
                    Capsule()
                        .fill(.white.opacity(isActive ? (isEmphasized ? 0.94 : 0.78) : 0.36))
                        .frame(
                            width: 2.5,
                            height: isActive && !reduceMotion ? 6 + CGFloat(amplitude) * 12 : 6
                        )
                }
            }
        }
        .frame(width: 26, height: 22)
    }
}

struct WallpaperSceneDropZoneView: View {
    @EnvironmentObject private var controller: WallpaperSceneController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulses = false

    private let tint = Color.indigo

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.48), lineWidth: 1.4)
                    .frame(width: 38, height: 38)
                    .scaleEffect(pulses ? 1.62 : 1)
                    .opacity(pulses ? 0 : 0.72)
                Image(systemName: controller.isHoveringDropZone ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(controller.isHoveringDropZone ? tint : .white)
                    .symbolEffect(.bounce, value: controller.isHoveringDropZone)
            }
            .frame(width: 48, height: 46)

            Text(controller.isHoveringDropZone ? "Release to create Scene" : "Create Wallpaper Scene")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(controller.isHoveringDropZone ? tint : .white.opacity(0.9))

            Text("Image, video, or .notchscene · stored locally")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(controller.isHoveringDropZone ? 0.2 : 0.07))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    controller.isHoveringDropZone ? tint.opacity(0.95) : .white.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 7])
                )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .animation(NotchMotion.dropTarget, value: controller.isHoveringDropZone)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(NotchAmbientMotion.shimmer()) { pulses = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Create wallpaper scene drop zone")
        .accessibilityHint("Drop one image, video, or MacFlow Scene package to import and apply it")
    }
}
