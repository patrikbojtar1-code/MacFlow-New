//
//  WallpaperSceneNotchView.swift
//  NotchLand
//
//  Hardware-safe compact control and drag target for NotchLand Scenes.
//

import AppKit
import SwiftUI

enum WallpaperSceneNotchMetrics {
    nonisolated static let compactSize = CGSize(width: 520, height: 50)
    nonisolated static let mediumSize = CGSize(width: 700, height: 78)
    nonisolated static let largeSize = CGSize(width: 760, height: 90)
    nonisolated static let dropSize = CGSize(width: 360, height: 138)

    nonisolated static func size(for notchSize: NotchSize) -> CGSize {
        switch notchSize {
        case .small: compactSize
        case .medium: mediumSize
        case .large: largeSize
        }
    }
}

struct WallpaperSceneCompactView: View {
    let scene: WallpaperScene

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var controller: WallpaperSceneController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatesScene = false

    private var notchSize: NotchSize {
        settings.notchContentSize
    }

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
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(NotchAmbientMotion.pulse(reduceMotion: reduceMotion)) {
                animatesScene = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wallpaper scene, \(scene.title)")
        .accessibilityValue(accessibilityValue)
    }

    private var identityWing: some View {
        HStack(spacing: notchSize == .small ? 9 : 12) {
            scenePreview
                .frame(
                    width: notchSize == .small ? 30 : 46,
                    height: notchSize == .small ? 30 : 46
                )
                .clipShape(RoundedRectangle(cornerRadius: notchSize == .small ? 9 : 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(scene.title)
                    .font(.system(size: NotchLayoutMetrics.compactTitleSize, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)

                if notchSize != .small {
                    Text(
                        controller.suspensionDetail
                            ?? controller.automationReason?.title
                            ?? "\(scene.kind.displayName) · \(controller.performance.effectiveProfile.title)"
                    )
                        .font(.system(size: NotchLayoutMetrics.compactSubtitleSize))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scenePreview: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image = NSImage(contentsOf: controller.library.previewURL(for: scene)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: scene.kind.systemImage)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .clipped()
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
                        animates: animatesScene
                    )
                }

                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: notchSize == .small ? 17 : 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: notchSize == .small ? 30 : 38, height: notchSize == .small ? 30 : 38)
                    .background(.white.opacity(0.08), in: Circle())
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
            }
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
    let animates: Bool

    private let heights: [CGFloat] = [7, 13, 18, 11, 16]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(.white.opacity(isActive ? 0.86 : 0.38))
                    .frame(width: 2.5, height: isActive && animates ? height : 5)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.48 + Double(index) * 0.07).repeatForever(autoreverses: true)
                            : NotchMotion.dismiss,
                        value: animates && isActive
                    )
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
        .accessibilityHint("Drop one image, video, or NotchLand Scene package to import and apply it")
    }
}
