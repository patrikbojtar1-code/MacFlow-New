//
//  WallpaperPreviewImage.swift
//  MacFlow
//
//  Cancelable, cached wallpaper preview loading that never performs file I/O
//  from a SwiftUI body evaluation.
//

import AppKit
import ImageIO
import SwiftUI

private struct DecodedWallpaperPreview: @unchecked Sendable {
    let image: CGImage
    let byteCost: Int
}

private actor WallpaperPreviewImageCache {
    static let shared = WallpaperPreviewImageCache()

    private var values: [URL: DecodedWallpaperPreview] = [:]
    private var order: [URL] = []
    private var totalBytes = 0
    private let maximumBytes = 96 * 1_024 * 1_024

    func image(for url: URL) async -> CGImage? {
        if let cached = values[url] {
            touch(url)
            return cached.image
        }

        let loaded = await Task.detached(priority: .userInitiated) { () -> DecodedWallpaperPreview? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return DecodedWallpaperPreview(
                image: image,
                byteCost: image.bytesPerRow * image.height
            )
        }.value
        guard let loaded else { return nil }

        values[url] = loaded
        touch(url)
        totalBytes += loaded.byteCost
        while totalBytes > maximumBytes, let oldest = order.first {
            order.removeFirst()
            if let removed = values.removeValue(forKey: oldest) {
                totalBytes -= removed.byteCost
            }
        }
        return loaded.image
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }
}

struct WallpaperPreviewImage: View {
    let scene: WallpaperScene
    let url: URL
    var scalingMode: WallpaperSceneRenderingConfiguration.ScalingMode = .fill
    var dimming: Double = 0
    var saturation: Double = 1
    var contrast: Double = 1
    var vignette: Double = 0
    var motionPreset: WallpaperSceneRenderingConfiguration.MotionPreset = .none
    var ambientEffect: WallpaperSceneRenderingConfiguration.AmbientEffect = .none
    var effectIntensity: Double = 0.45
    var parallaxStrength: Double = 0
    var musicReaction: WallpaperSceneRenderingConfiguration.MusicReaction = .none
    var musicReactionIntensity: Double = 0.45
    var composerLayers = WallpaperSceneRenderingConfiguration.defaultComposerLayers
    var animatesMotion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?
    @State private var motionPhase = false
    @State private var parallaxPosition = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                ForEach(composerLayers) { composerLayer in
                    if composerLayer.isVisible, composerLayer.opacity > 0.001 {
                        WallpaperComposerLayerAnimation(layer: composerLayer) {
                            previewLayer(composerLayer.kind, size: proxy.size)
                                .scaleEffect(composerLayer.scale)
                                .offset(
                                    x: proxy.size.width * composerLayer.offsetX,
                                    y: proxy.size.height * -composerLayer.offsetY
                                )
                                .blur(radius: composerLayer.blurRadius)
                                .mask {
                                    composerLayerMask(composerLayer, size: proxy.size)
                                }
                        }
                            .opacity(composerLayer.opacity)
                            .blendMode(composerLayer.blendMode.swiftUIBlendMode)
                    }
                }
            }
            .animation(AppMotion.stateChange(reduceMotion: reduceMotion), value: composerLayers)
            .onContinuousHover { phase in
                guard animatesMotion, !reduceMotion, parallaxStrength > 0 else {
                    parallaxPosition = CGPoint(x: 0.5, y: 0.5)
                    return
                }
                switch phase {
                case .active(let location):
                    parallaxPosition = CGPoint(
                        x: min(max(location.x / max(proxy.size.width, 1), 0), 1),
                        y: min(max(location.y / max(proxy.size.height, 1), 0), 1)
                    )
                case .ended:
                    withAnimation(.easeOut(duration: 0.2)) {
                        parallaxPosition = CGPoint(x: 0.5, y: 0.5)
                    }
                }
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            guard let loadedImage = await WallpaperPreviewImageCache.shared.image(for: url),
                  !Task.isCancelled else { return }
            withAnimation(AppMotion.insertion(reduceMotion: reduceMotion)) {
                image = loadedImage
            }
        }
        .task(id: motionPreset) {
            motionPhase = false
            guard animatesMotion, !reduceMotion, motionPreset != .none else { return }
            await Task.yield()
            withAnimation(
                .easeInOut(duration: motionPreset == .cinematicZoom ? 12 : 16)
                    .repeatForever(autoreverses: true)
            ) {
                motionPhase = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scene.title), \(scene.kind.displayName) wallpaper")
    }

    @ViewBuilder
    private func composerLayerMask(
        _ composerLayer: WallpaperSceneRenderingConfiguration.ComposerLayer,
        size: CGSize
    ) -> some View {
        let visible = Color.white
        let hidden = Color.white.opacity(0)
        switch composerLayer.maskStyle {
        case .none:
            visible
        case .fadeTop, .fadeBottom:
            LinearGradient(
                stops: composerLayer.isMaskInverted
                    ? [
                        .init(color: visible, location: 0),
                        .init(color: hidden, location: composerLayer.maskFeather),
                        .init(color: hidden, location: 1),
                    ]
                    : [
                        .init(color: hidden, location: 0),
                        .init(color: visible, location: composerLayer.maskFeather),
                        .init(color: visible, location: 1),
                    ],
                startPoint: composerLayer.maskStyle == .fadeTop ? .top : .bottom,
                endPoint: composerLayer.maskStyle == .fadeTop ? .bottom : .top
            )
        case .focusCenter:
            RadialGradient(
                stops: composerLayer.isMaskInverted
                    ? [
                        .init(color: hidden, location: 0),
                        .init(color: hidden, location: 1 - composerLayer.maskFeather),
                        .init(color: visible, location: 1),
                    ]
                    : [
                        .init(color: visible, location: 0),
                        .init(color: visible, location: 1 - composerLayer.maskFeather),
                        .init(color: hidden, location: 1),
                    ],
                center: .center,
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.72
            )
        }
    }

    @ViewBuilder
    private func previewLayer(
        _ kind: WallpaperSceneRenderingConfiguration.ComposerLayer.Kind,
        size: CGSize
    ) -> some View {
        switch kind {
        case .media:
            if let image {
                imageView(image, size: size)
                    .scaleEffect(motionScale * parallaxScale)
                    .offset(combinedOffset)
                    .saturation(saturation)
                    .contrast(contrast)
                    .transition(.opacity)
            } else {
                Image(systemName: scene.kind.systemImage)
                    .font(.title2.weight(.light))
                    .foregroundStyle(.white.opacity(0.42))
            }
        case .musicGlow:
            if animatesMotion, !reduceMotion, musicReaction != .none {
                WallpaperMusicReactionPreview(
                    reaction: musicReaction,
                    intensity: musicReactionIntensity
                )
                .allowsHitTesting(false)
            }
        case .atmosphere:
            if animatesMotion, !reduceMotion, ambientEffect != .none {
                WallpaperAmbientEffectPreview(
                    effect: ambientEffect,
                    intensity: effectIntensity
                )
                .allowsHitTesting(false)
            }
        case .vignette:
            RadialGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(vignette * 0.28), location: 0.72),
                    .init(color: .black.opacity(vignette), location: 1),
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.72
            )
            .allowsHitTesting(false)
        case .dimming:
            Color.black.opacity(dimming)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func imageView(_ image: CGImage, size: CGSize) -> some View {
        switch scalingMode {
        case .fill:
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        case .fit:
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        case .stretch:
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
        }
    }

    private var motionScale: CGFloat {
        guard animatesMotion, !reduceMotion else { return 1 }
        switch motionPreset {
        case .none: return 1
        case .cinematicZoom: return motionPhase ? 1.055 : 1.01
        case .slowDrift: return motionPhase ? 1.075 : 1.045
        }
    }

    private var motionOffset: CGSize {
        guard animatesMotion, !reduceMotion, motionPreset == .slowDrift else { return .zero }
        return motionPhase ? CGSize(width: 7, height: -5) : CGSize(width: -6, height: 4)
    }

    private var parallaxScale: CGFloat {
        guard animatesMotion, !reduceMotion else { return 1 }
        return 1 + (0.025 * parallaxStrength)
    }

    private var combinedOffset: CGSize {
        let pointerX = (parallaxPosition.x - 0.5) * 2
        let pointerY = (parallaxPosition.y - 0.5) * 2
        let maximumOffset = 9 * parallaxStrength
        return CGSize(
            width: motionOffset.width + (pointerX * maximumOffset),
            height: motionOffset.height + (pointerY * maximumOffset)
        )
    }
}

private struct WallpaperAmbientEffectPreview: View {
    private enum Tokens {
        static let particleCount = 12
    }

    let effect: WallpaperSceneRenderingConfiguration.AmbientEffect
    let intensity: Double

    @State private var phase = false

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<Tokens.particleCount, id: \.self) { index in
                Circle()
                    .fill(particleColor.opacity(particleOpacity(index)))
                    .frame(width: particleSize(index), height: particleSize(index))
                    .blur(radius: effect == .dust ? 1.1 : 0.35)
                    .position(
                        x: horizontalPosition(index, width: proxy.size.width),
                        y: verticalPosition(index, height: proxy.size.height)
                    )
                    .animation(
                        .linear(duration: particleDuration(index))
                            .repeatForever(autoreverses: false)
                            .delay(Double(index % 5) * 0.32),
                        value: phase
                    )
            }
        }
        .task(id: effect) {
            phase = false
            await Task.yield()
            phase = true
        }
    }

    private var particleColor: Color {
        effect == .embers ? .orange : .white
    }

    private func particleSize(_ index: Int) -> CGFloat {
        CGFloat(2.4 + Double(index % 4) * 1.15) * (0.72 + intensity * 0.5)
    }

    private func particleOpacity(_ index: Int) -> Double {
        min(0.18 + (Double(index % 3) * 0.07), 0.42) * (0.55 + intensity * 0.45)
    }

    private func particleDuration(_ index: Int) -> Double {
        let base = effect == .dust ? 13.0 : (effect == .snow ? 9.5 : 7.5)
        return base + Double(index % 5) * 0.8
    }

    private func horizontalPosition(_ index: Int, width: CGFloat) -> CGFloat {
        let base = CGFloat((index * 37) % 101) / 100
        let drift = phase ? CGFloat((index % 3) - 1) * 18 : 0
        return (base * width) + drift
    }

    private func verticalPosition(_ index: Int, height: CGFloat) -> CGFloat {
        let stagger = CGFloat((index * 29) % 100) / 100 * height
        switch effect {
        case .none:
            return stagger
        case .dust:
            return phase ? stagger - 28 : stagger + 24
        case .snow:
            return phase ? height + 24 : -24 - stagger * 0.2
        case .embers:
            return phase ? -24 : height + 24 + stagger * 0.15
        }
    }
}

private struct WallpaperMusicReactionPreview: View {
    let reaction: WallpaperSceneRenderingConfiguration.MusicReaction
    let intensity: Double

    @State private var phase = false

    var body: some View {
        RadialGradient(
            stops: [
                .init(color: MacFlowColor.wallpaper.opacity(0.72), location: 0),
                .init(color: Color.indigo.opacity(0.24), location: 0.5),
                .init(color: .clear, location: 1),
            ],
            center: .top,
            startRadius: 0,
            endRadius: 420
        )
        .opacity(glowOpacity)
        .blendMode(.plusLighter)
        .task(id: reaction) {
            phase = false
            await Task.yield()
            withAnimation(
                .easeInOut(duration: reaction == .ambientGlow ? 2.8 : 1.25)
                    .repeatForever(autoreverses: true)
            ) {
                phase = true
            }
        }
    }

    private var glowOpacity: Double {
        let low = 0.08 + (intensity * 0.04)
        let high = 0.18 + (intensity * 0.24)
        return phase ? high : low
    }
}

private struct WallpaperComposerLayerAnimation<Content: View>: View {
    let layer: WallpaperSceneRenderingConfiguration.ComposerLayer
    private let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    init(
        layer: WallpaperSceneRenderingConfiguration.ComposerLayer,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.layer = layer
        self.content = content
    }

    var body: some View {
        content()
            .scaleEffect(animatedScale)
            .offset(animatedOffset)
            .opacity(animatedOpacity)
            .task(id: layer) {
                phase = false
                guard layer.animationPreset != .none, !reduceMotion else { return }
                await Task.yield()
                withAnimation(
                    .easeInOut(duration: layer.animationDuration / 2)
                        .repeatForever(autoreverses: true)
                ) {
                    phase = true
                }
            }
    }

    private var animatedScale: CGFloat {
        guard layer.animationPreset == .breathe else { return 1 }
        return phase ? 1 + (0.035 * layer.animationAmount) : 1
    }

    private var animatedOffset: CGSize {
        guard layer.animationPreset == .float else { return .zero }
        let amount = layer.animationAmount
        return phase
            ? CGSize(width: 10 * amount, height: -6 * amount)
            : CGSize(width: -10 * amount, height: 5 * amount)
    }

    private var animatedOpacity: Double {
        guard layer.animationPreset == .pulse else { return 1 }
        return phase ? max(0.65, 1 - (0.28 * layer.animationAmount)) : 1
    }
}

private extension WallpaperSceneRenderingConfiguration.ComposerLayer.BlendMode {
    var swiftUIBlendMode: SwiftUI.BlendMode {
        switch self {
        case .normal: .normal
        case .screen: .screen
        case .add: .plusLighter
        case .softLight: .softLight
        case .multiply: .multiply
        }
    }
}
