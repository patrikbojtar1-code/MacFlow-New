//
//  WallpaperSceneWindow.swift
//  NotchLand
//
//  A mouse-transparent desktop renderer for a single display.
//

import AppKit
import AVFoundation
import CoreImage
import ImageIO
import QuartzCore

nonisolated struct WallpaperMediaPlaybackSnapshot: Equatable, Sendable {
    var isPlaying: Bool
    var accentRed: Double
    var accentGreen: Double
    var accentBlue: Double

    static let inactive = WallpaperMediaPlaybackSnapshot(
        isPlaying: false,
        accentRed: 0.28,
        accentGreen: 0.52,
        accentBlue: 1
    )
}

nonisolated struct WallpaperSceneEffectDiagnostics: Equatable, Sendable {
    var ambientLayerAttached: Bool
    var ambientParticleBirthRate: Float
    var musicGlowAnimating: Bool
    var composerLayerOrder: [WallpaperSceneRenderingConfiguration.ComposerLayer.Kind]
    var hiddenComposerLayers: Set<WallpaperSceneRenderingConfiguration.ComposerLayer.Kind>
    var transformedComposerLayers: Set<WallpaperSceneRenderingConfiguration.ComposerLayer.Kind>
    var blurredComposerLayers: Set<WallpaperSceneRenderingConfiguration.ComposerLayer.Kind>
    var maskedComposerLayers: Set<WallpaperSceneRenderingConfiguration.ComposerLayer.Kind>
    var animatedComposerLayers: Set<WallpaperSceneRenderingConfiguration.ComposerLayer.Kind>
}

@MainActor
final class WallpaperSceneWindow: NSWindow {
    private let rendererView = WallpaperSceneRenderView()
    let displayID: CGDirectDisplayID
    private(set) var rendererID: UUID?
    private var currentAssetURL: URL?
    private var rendererEventHandler: (@MainActor (UUID, WallpaperRendererEvent) -> Void)?

    init(screen: NSScreen) {
        displayID = screen.displayID ?? 0
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = rendererView
        setFrame(screen.frame, display: false)
    }

    func display(
        scene: WallpaperScene,
        assetURL: URL,
        profile: WallpaperPerformanceProfile,
        paused: Bool,
        onReady: (@MainActor () -> Void)? = nil,
        onRendererEvent: (@MainActor (UUID, WallpaperRendererEvent) -> Void)? = nil
    ) {
        let isNewRenderer = currentAssetURL != assetURL || rendererID == nil
        if isNewRenderer {
            notifyRendererStopped()
            rendererID = UUID()
            currentAssetURL = assetURL
        }
        rendererEventHandler = onRendererEvent
        let activeRendererID = rendererID
        if isNewRenderer, let activeRendererID {
            onRendererEvent?(
                activeRendererID,
                .rendererCreated(hasPlayer: scene.kind == .video)
            )
        }
        rendererView.display(
            scene: scene,
            assetURL: assetURL,
            profile: profile,
            onReady: onReady,
            onRendererEvent: { [weak self] event in
                guard let self,
                      let activeRendererID,
                      self.rendererID == activeRendererID else { return }
                self.rendererEventHandler?(activeRendererID, event)
            }
        )
        rendererView.setPaused(paused)
        orderFrontRegardless()
    }

    func update(
        profile: WallpaperPerformanceProfile,
        rendering: WallpaperSceneRenderingConfiguration,
        paused: Bool
    ) {
        rendererView.update(profile: profile)
        rendererView.update(rendering: rendering)
        rendererView.setPaused(paused)
    }

    func update(mediaPlayback: WallpaperMediaPlaybackSnapshot) {
        rendererView.update(mediaPlayback: mediaPlayback)
    }

    func stopRendering() {
        notifyRendererStopped()
        rendererView.stop()
        currentAssetURL = nil
        orderOut(nil)
    }

    private func notifyRendererStopped() {
        guard let rendererID else { return }
        rendererEventHandler?(rendererID, .stopped)
        self.rendererID = nil
        rendererEventHandler = nil
    }
}

@MainActor
final class WallpaperSceneRenderView: NSView {
    private enum Motion {
        static let treatmentDuration: CFTimeInterval = 0.18
        static let animationKey = "macflow.scene.motion"
        static let musicGlowAnimationKey = "macflow.scene.music.glow"
        static let particlePulseAnimationKey = "macflow.scene.music.particles"
        static let composerAnimationKey = "macflow.scene.composer.keyframes"
        static let zoomDuration: CFTimeInterval = 24
        static let driftDuration: CFTimeInterval = 32
    }

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoLayer: AVPlayerLayer?
    private var imageLayer: CALayer?
    private var currentAssetURL: URL?
    private var currentKind: WallpaperScene.Kind?
    private var imageLoadTask: Task<Void, Never>?
    private var currentRendering = WallpaperSceneRenderingConfiguration.default
    private var currentProfile = WallpaperPerformanceProfile.automatic
    private var currentMediaPlayback = WallpaperMediaPlaybackSnapshot.inactive
    private var isPaused = false
    private var activeComposerAnimationKinds = Set<
        WallpaperSceneRenderingConfiguration.ComposerLayer.Kind
    >()
    private let mediaContainerLayer = CALayer()
    private let mediaAnimationLayer = CALayer()
    private let mediaMotionLayer = CALayer()
    private let musicContainerLayer = CALayer()
    private let musicAnimationLayer = CALayer()
    private let atmosphereContainerLayer = CALayer()
    private let atmosphereAnimationLayer = CALayer()
    private let vignetteContainerLayer = CALayer()
    private let vignetteAnimationLayer = CALayer()
    private let dimmingContainerLayer = CALayer()
    private let dimmingAnimationLayer = CALayer()
    private var emitterLayer: CAEmitterLayer?
    private var pointerSubscriptionID: UUID?
    private let musicGlowLayer = CAGradientLayer()
    private let vignetteLayer = CAGradientLayer()
    private let dimmingLayer = CALayer()
    private lazy var composerMaskLayers: [
        WallpaperSceneRenderingConfiguration.ComposerLayer.Kind: CAGradientLayer
    ] = Dictionary(uniqueKeysWithValues:
        WallpaperSceneRenderingConfiguration.ComposerLayer.Kind.allCases.map {
            ($0, CAGradientLayer())
        }
    )
    private var itemStatusObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?
    private var readyForDisplayObservation: NSKeyValueObservation?
    private var accessLogObserver: NSObjectProtocol?
    private var rendererEvent: (@MainActor (WallpaperRendererEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        mediaContainerLayer.masksToBounds = false
        mediaMotionLayer.masksToBounds = false
        mediaContainerLayer.addSublayer(mediaAnimationLayer)
        mediaAnimationLayer.addSublayer(mediaMotionLayer)
        musicGlowLayer.type = .radial
        musicGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.18)
        musicGlowLayer.endPoint = CGPoint(x: 0.5, y: 0.95)
        musicGlowLayer.locations = [0, 0.52, 1]
        musicGlowLayer.opacity = 0
        vignetteLayer.type = .radial
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1, y: 1)
        vignetteLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.22).cgColor,
            NSColor.black.cgColor,
        ]
        vignetteLayer.locations = [0, 0.62, 1]
        vignetteLayer.opacity = 0
        dimmingLayer.backgroundColor = NSColor.black.cgColor
        dimmingLayer.opacity = 0
        musicContainerLayer.addSublayer(musicAnimationLayer)
        musicAnimationLayer.addSublayer(musicGlowLayer)
        atmosphereContainerLayer.addSublayer(atmosphereAnimationLayer)
        vignetteContainerLayer.addSublayer(vignetteAnimationLayer)
        vignetteAnimationLayer.addSublayer(vignetteLayer)
        dimmingContainerLayer.addSublayer(dimmingAnimationLayer)
        dimmingAnimationLayer.addSublayer(dimmingLayer)
        applyComposerLayerStack()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var effectDiagnostics: WallpaperSceneEffectDiagnostics {
        let containers = composerContainers
        let orderedLayers = layer?.sublayers?.compactMap { candidate in
            containers.first(where: { $0.value === candidate })?.key
        } ?? []
        return WallpaperSceneEffectDiagnostics(
            ambientLayerAttached: emitterLayer?.superlayer === atmosphereAnimationLayer,
            ambientParticleBirthRate: emitterLayer?.emitterCells?.first?.birthRate ?? 0,
            musicGlowAnimating: musicGlowLayer.animation(
                forKey: Motion.musicGlowAnimationKey
            ) != nil,
            composerLayerOrder: orderedLayers,
            hiddenComposerLayers: Set(containers.compactMap { entry in
                entry.value.isHidden ? entry.key : nil
            }),
            transformedComposerLayers: Set(containers.compactMap { entry in
                entry.value.affineTransform().isIdentity ? nil : entry.key
            }),
            blurredComposerLayers: Set(containers.compactMap { entry in
                entry.value.filters?.isEmpty == false ? entry.key : nil
            }),
            maskedComposerLayers: Set(containers.compactMap { entry in
                entry.value.mask == nil ? nil : entry.key
            }),
            animatedComposerLayers: activeComposerAnimationKinds
        )
    }

    override func layout() {
        super.layout()
        applyComposerLayerStack(animated: false)
        let contentBounds = CGRect(origin: .zero, size: bounds.size)
        composerAnimationLayers.values.forEach { $0.frame = contentBounds }
        mediaMotionLayer.frame = contentBounds
        imageLayer?.frame = contentBounds
        videoLayer?.frame = contentBounds
        layoutEmitterLayer()
        musicGlowLayer.frame = contentBounds
        vignetteLayer.frame = contentBounds
        dimmingLayer.frame = contentBounds
    }

    private var composerContainers: [
        WallpaperSceneRenderingConfiguration.ComposerLayer.Kind: CALayer
    ] {
        [
            .media: mediaContainerLayer,
            .musicGlow: musicContainerLayer,
            .atmosphere: atmosphereContainerLayer,
            .vignette: vignetteContainerLayer,
            .dimming: dimmingContainerLayer,
        ]
    }

    private var composerAnimationLayers: [
        WallpaperSceneRenderingConfiguration.ComposerLayer.Kind: CALayer
    ] {
        [
            .media: mediaAnimationLayer,
            .musicGlow: musicAnimationLayer,
            .atmosphere: atmosphereAnimationLayer,
            .vignette: vignetteAnimationLayer,
            .dimming: dimmingAnimationLayer,
        ]
    }

    private func applyComposerLayerStack(animated: Bool = false) {
        let containers = composerContainers
        let orderedContainers = currentRendering.composerLayers.compactMap {
            containers[$0.kind]
        }
        let currentContainers = layer?.sublayers?.filter { candidate in
            containers.values.contains { $0 === candidate }
        } ?? []
        let requiresReordering = currentContainers.count != orderedContainers.count
            || zip(currentContainers, orderedContainers).contains { pair in
                pair.0 !== pair.1
            }

        CATransaction.begin()
        let shouldAnimate = animated
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.setDisableActions(!shouldAnimate)
        CATransaction.setAnimationDuration(shouldAnimate ? Motion.treatmentDuration : 0)
        if requiresReordering {
            containers.values.forEach { $0.removeFromSuperlayer() }
            orderedContainers.forEach { layer?.addSublayer($0) }
        }
        for composerLayer in currentRendering.composerLayers {
            guard let container = containers[composerLayer.kind] else { continue }
            container.isHidden = !composerLayer.isVisible
            container.opacity = Float(composerLayer.opacity)
            container.compositingFilter = Self.compositingFilter(
                for: composerLayer.blendMode
            )
            applyGeometry(of: composerLayer, to: container)
        }
        CATransaction.commit()
    }

    private func applyGeometry(
        of composerLayer: WallpaperSceneRenderingConfiguration.ComposerLayer,
        to container: CALayer
    ) {
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        container.bounds = CGRect(origin: .zero, size: bounds.size)
        container.position = CGPoint(
            x: bounds.midX + (bounds.width * composerLayer.offsetX),
            y: bounds.midY + (bounds.height * composerLayer.offsetY)
        )
        container.setAffineTransform(CGAffineTransform(
            scaleX: composerLayer.scale,
            y: composerLayer.scale
        ))

        let effectiveBlur = composerLayer.blurRadius
            * WallpaperSceneEffectsPolicy.blurMultiplier(for: currentProfile)
        if effectiveBlur > 0.01,
           let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(effectiveBlur, forKey: kCIInputRadiusKey)
            container.filters = [blur]
        } else {
            container.filters = nil
        }
        applyMask(of: composerLayer, to: container)
    }

    private func applyMask(
        of composerLayer: WallpaperSceneRenderingConfiguration.ComposerLayer,
        to container: CALayer
    ) {
        guard composerLayer.maskStyle != .none,
              let maskLayer = composerMaskLayers[composerLayer.kind] else {
            container.mask = nil
            return
        }

        let visible = NSColor.white.cgColor
        let hidden = NSColor.white.withAlphaComponent(0).cgColor
        maskLayer.frame = container.bounds

        switch composerLayer.maskStyle {
        case .none:
            container.mask = nil
            return
        case .fadeTop, .fadeBottom:
            maskLayer.type = .axial
            if composerLayer.maskStyle == .fadeTop {
                maskLayer.startPoint = CGPoint(x: 0.5, y: 1)
                maskLayer.endPoint = CGPoint(x: 0.5, y: 0)
            } else {
                maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
                maskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            }
            maskLayer.colors = composerLayer.isMaskInverted
                ? [visible, hidden, hidden]
                : [hidden, visible, visible]
            maskLayer.locations = [0, NSNumber(value: composerLayer.maskFeather), 1]
        case .focusCenter:
            maskLayer.type = .radial
            maskLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            maskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            maskLayer.colors = composerLayer.isMaskInverted
                ? [hidden, hidden, visible]
                : [visible, visible, hidden]
            maskLayer.locations = [
                0,
                NSNumber(value: 1 - composerLayer.maskFeather),
                1,
            ]
        }
        container.mask = maskLayer
    }

    private static func compositingFilter(
        for blendMode: WallpaperSceneRenderingConfiguration.ComposerLayer.BlendMode
    ) -> Any? {
        let filterName: String?
        switch blendMode {
        case .normal:
            filterName = nil
        case .screen:
            filterName = "CIScreenBlendMode"
        case .add:
            filterName = "CIAdditionCompositing"
        case .softLight:
            filterName = "CISoftLightBlendMode"
        case .multiply:
            filterName = "CIMultiplyBlendMode"
        }
        return filterName.flatMap(CIFilter.init(name:))
    }

    private func isComposerLayerRenderable(
        _ kind: WallpaperSceneRenderingConfiguration.ComposerLayer.Kind
    ) -> Bool {
        guard let composerLayer = currentRendering.composerLayers.first(where: {
            $0.kind == kind
        }) else { return false }
        return composerLayer.isVisible && composerLayer.opacity > 0.001
    }

    func display(
        scene: WallpaperScene,
        assetURL: URL,
        profile: WallpaperPerformanceProfile,
        onReady: (@MainActor () -> Void)? = nil,
        onRendererEvent: (@MainActor (WallpaperRendererEvent) -> Void)? = nil
    ) {
        if currentAssetURL == assetURL, currentKind == scene.kind {
            rendererEvent = onRendererEvent
            update(profile: profile)
            update(rendering: scene.rendering)
            Task { @MainActor in onReady?() }
            return
        }

        stop()
        rendererEvent = onRendererEvent
        currentAssetURL = assetURL
        currentKind = scene.kind
        currentRendering = scene.rendering.normalized
        currentProfile = profile

        switch scene.kind {
        case .image:
            displayImage(at: assetURL, onReady: onReady)
        case .video:
            displayVideo(at: assetURL, profile: profile)
            // Preserve current runtime behavior during the measurement phase.
            // Telemetry separately records when AVPlayerLayer presents a frame.
            Task { @MainActor in onReady?() }
        }
        update(rendering: currentRendering, animated: false)
    }

    func update(profile: WallpaperPerformanceProfile) {
        currentProfile = profile
        let maximumResolution: CGSize
        switch profile {
        case .eco:
            maximumResolution = CGSize(width: 1_280, height: 720)
        case .automatic, .balanced:
            maximumResolution = CGSize(width: 1_920, height: 1_080)
        case .cinematic:
            maximumResolution = .zero
        }
        player?.items().forEach { $0.preferredMaximumResolution = maximumResolution }
        applyComposerLayerStack(animated: false)
        updateComposerLayerAnimations()
        updateImageMotion()
        updateAmbientEffect()
        updateMusicReaction()
        updateParallaxSubscription()
    }

    func update(rendering: WallpaperSceneRenderingConfiguration) {
        update(rendering: rendering, animated: true)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if let player {
            if paused {
                player.pause()
            } else if player.timeControlStatus != .playing {
                player.playImmediately(atRate: Float(currentRendering.playbackRate))
            }
        }
        updateImageMotion()
        updateComposerLayerAnimations()
        updateAmbientEffect()
        updateMusicReaction()
        updateParallaxSubscription()
    }

    func update(mediaPlayback: WallpaperMediaPlaybackSnapshot) {
        guard currentMediaPlayback != mediaPlayback else { return }
        currentMediaPlayback = mediaPlayback
        updateMusicReaction()
    }

    func stop() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        itemStatusObservation = nil
        keepUpObservation = nil
        readyForDisplayObservation = nil
        if let accessLogObserver {
            NotificationCenter.default.removeObserver(accessLogObserver)
            self.accessLogObserver = nil
        }
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        videoLayer?.removeFromSuperlayer()
        videoLayer = nil
        imageLayer?.removeFromSuperlayer()
        imageLayer = nil
        emitterLayer?.removeFromSuperlayer()
        emitterLayer = nil
        musicGlowLayer.removeAllAnimations()
        musicGlowLayer.opacity = 0
        composerAnimationLayers.values.forEach { $0.removeAllAnimations() }
        activeComposerAnimationKinds.removeAll()
        removePointerSubscription()
        mediaMotionLayer.setAffineTransform(.identity)
        isPaused = false
        currentAssetURL = nil
        currentKind = nil
        rendererEvent = nil
    }

    private func displayImage(at url: URL, onReady: (@MainActor () -> Void)?) {
        imageLoadTask?.cancel()
        imageLoadTask = Task { @MainActor [weak self] in
            let cgImage: CGImage? = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(
                    source,
                    0,
                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                )
            }.value
            guard let self, !Task.isCancelled, self.currentAssetURL == url else { return }
            guard let cgImage else {
                self.rendererEvent?(.failed("Image decoding failed"))
                return
            }

            let imageLayer = CALayer()
            imageLayer.contents = cgImage
            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.contentsScale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            imageLayer.frame = self.bounds
            self.mediaMotionLayer.addSublayer(imageLayer)
            self.imageLayer = imageLayer
            self.applyColorGrading()
            self.updateImageMotion()
            self.imageLoadTask = nil
            self.rendererEvent?(.firstFramePresented)
            onReady?()
        }
    }

    private func displayVideo(at url: URL, profile: WallpaperPerformanceProfile) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none

        let looper = AVPlayerLooper(player: player, templateItem: item)
        let videoLayer = AVPlayerLayer(player: player)
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.frame = bounds
        mediaMotionLayer.addSublayer(videoLayer)

        self.player = player
        self.looper = looper
        self.videoLayer = videoLayer
        applyColorGrading()
        observeReadiness(item: item, layer: videoLayer, assetURL: url)
        update(profile: profile)
        player.playImmediately(atRate: Float(currentRendering.playbackRate))
    }

    private func observeReadiness(
        item: AVPlayerItem,
        layer: AVPlayerLayer,
        assetURL: URL
    ) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.currentAssetURL == assetURL else { return }
                switch status {
                case .readyToPlay:
                    self.rendererEvent?(.playerItemReady)
                case .failed:
                    self.rendererEvent?(.failed(message ?? "AVPlayerItem failed"))
                case .unknown:
                    break
                @unknown default:
                    self.rendererEvent?(.failed("Unknown AVPlayerItem state"))
                }
            }
        }

        keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
            guard item.isPlaybackLikelyToKeepUp else { return }
            Task { @MainActor [weak self] in
                guard let self, self.currentAssetURL == assetURL else { return }
                self.rendererEvent?(.playbackLikelyToKeepUp)
            }
        }

        readyForDisplayObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self] in
                guard let self, self.currentAssetURL == assetURL else { return }
                self.rendererEvent?(.firstFramePresented)
            }
        }

        accessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.currentAssetURL == assetURL,
                      let event = item.accessLog()?.events.last else { return }
                let bitrate = event.observedBitrate.isFinite && event.observedBitrate > 0
                    ? Int(event.observedBitrate.rounded())
                    : nil
                self.rendererEvent?(.accessLog(
                    droppedFrames: event.numberOfDroppedVideoFrames,
                    observedBitrate: bitrate
                ))
            }
        }
    }

    private func update(
        rendering: WallpaperSceneRenderingConfiguration,
        animated: Bool
    ) {
        let normalized = rendering.normalized
        currentRendering = normalized
        applyComposerLayerStack(animated: animated)

        CATransaction.begin()
        CATransaction.setAnimationDuration(
            animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? Motion.treatmentDuration
                : 0
        )
        imageLayer?.contentsGravity = normalized.scalingMode.contentsGravity
        videoLayer?.videoGravity = normalized.scalingMode.videoGravity
        vignetteLayer.opacity = Float(normalized.vignette)
        dimmingLayer.opacity = Float(normalized.dimming)
        CATransaction.commit()

        applyColorGrading()
        updateComposerLayerAnimations()
        updateImageMotion()
        updateAmbientEffect()
        updateMusicReaction()
        updateParallaxSubscription()

        guard let player else { return }
        player.defaultRate = Float(normalized.playbackRate)
        if player.timeControlStatus == .playing {
            player.playImmediately(atRate: Float(normalized.playbackRate))
        }
    }

    private func applyColorGrading() {
        let usesDefaultGrading = abs(currentRendering.saturation - 1) < 0.001
            && abs(currentRendering.contrast - 1) < 0.001
        let filters: [Any]?
        if usesDefaultGrading {
            filters = nil
        } else if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(currentRendering.saturation, forKey: kCIInputSaturationKey)
            colorControls.setValue(currentRendering.contrast, forKey: kCIInputContrastKey)
            filters = [colorControls]
        } else {
            filters = nil
        }
        imageLayer?.filters = filters
        videoLayer?.filters = filters
    }

    private func updateComposerLayerAnimations() {
        let animationLayers = composerAnimationLayers
        animationLayers.values.forEach {
            $0.removeAnimation(forKey: Motion.composerAnimationKey)
        }
        activeComposerAnimationKinds.removeAll(keepingCapacity: true)

        guard !isPaused,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let maximumLayers = WallpaperSceneEffectsPolicy.maximumAnimatedLayers(
            for: currentProfile
        )
        let profileAmount = WallpaperSceneEffectsPolicy.animationAmountMultiplier(
            for: currentProfile
        )
        var animatedLayerCount = 0

        for composerLayer in currentRendering.composerLayers {
            guard animatedLayerCount < maximumLayers,
                  composerLayer.animationPreset != .none,
                  isComposerLayerRenderable(composerLayer.kind),
                  let animationLayer = animationLayers[composerLayer.kind],
                  let animation = makeComposerAnimation(
                    for: composerLayer,
                    amountMultiplier: profileAmount
                  ) else { continue }
            animationLayer.add(animation, forKey: Motion.composerAnimationKey)
            activeComposerAnimationKinds.insert(composerLayer.kind)
            animatedLayerCount += 1
        }
    }

    private func makeComposerAnimation(
        for composerLayer: WallpaperSceneRenderingConfiguration.ComposerLayer,
        amountMultiplier: Double
    ) -> CAAnimation? {
        let amount = composerLayer.animationAmount * amountMultiplier
        let duration = composerLayer.animationDuration
        let animation: CAAnimation

        switch composerLayer.animationPreset {
        case .none:
            return nil
        case .breathe:
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1, 1 + (0.035 * amount), 1]
            scale.keyTimes = [0, 0.5, 1]
            animation = scale
        case .float:
            let horizontal = CAKeyframeAnimation(keyPath: "transform.translation.x")
            horizontal.values = [-10 * amount, 10 * amount, -10 * amount]
            horizontal.keyTimes = [0, 0.5, 1]
            horizontal.duration = duration
            let vertical = CAKeyframeAnimation(keyPath: "transform.translation.y")
            vertical.values = [5 * amount, -6 * amount, 5 * amount]
            vertical.keyTimes = [0, 0.5, 1]
            vertical.duration = duration
            let group = CAAnimationGroup()
            group.animations = [horizontal, vertical]
            animation = group
        case .pulse:
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [1, max(0.65, 1 - (0.28 * amount)), 1]
            opacity.keyTimes = [0, 0.5, 1]
            animation = opacity
        }

        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = true
        return animation
    }

    private func updateImageMotion() {
        guard let imageLayer else { return }
        imageLayer.removeAnimation(forKey: Motion.animationKey)
        imageLayer.speed = 1
        imageLayer.timeOffset = 0
        imageLayer.beginTime = 0

        guard WallpaperSceneMotionPolicy.shouldAnimate(
            preset: currentRendering.motionPreset,
            kind: currentKind,
            profile: currentProfile,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            paused: isPaused
        ), isComposerLayerRenderable(.media) else { return }

        let animation: CAAnimation
        switch currentRendering.motionPreset {
        case .none:
            return
        case .cinematicZoom:
            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = 1.01
            zoom.toValue = 1.065
            zoom.duration = Motion.zoomDuration
            zoom.autoreverses = true
            zoom.repeatCount = .infinity
            zoom.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation = zoom
        case .slowDrift:
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1.055, 1.085, 1.055]
            let horizontal = CAKeyframeAnimation(keyPath: "transform.translation.x")
            horizontal.values = [-10, 12, -10]
            let vertical = CAKeyframeAnimation(keyPath: "transform.translation.y")
            vertical.values = [7, -9, 7]
            let group = CAAnimationGroup()
            group.animations = [scale, horizontal, vertical]
            group.duration = Motion.driftDuration
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation = group
        }
        imageLayer.add(animation, forKey: Motion.animationKey)
    }

    private func updateAmbientEffect() {
        emitterLayer?.removeFromSuperlayer()
        emitterLayer = nil

        guard isComposerLayerRenderable(.atmosphere),
              WallpaperSceneEffectsPolicy.shouldRender(
            effect: currentRendering.ambientEffect,
            profile: currentProfile,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            paused: isPaused
        ) else { return }

        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.birthRate = 1
        emitter.lifetime = 1
        emitter.renderMode = .unordered
        emitter.masksToBounds = true
        emitter.emitterCells = [makeEmitterCell(for: currentRendering.ambientEffect)]
        atmosphereAnimationLayer.addSublayer(emitter)
        emitterLayer = emitter
        layoutEmitterLayer()
    }

    private func makeEmitterCell(
        for effect: WallpaperSceneRenderingConfiguration.AmbientEffect
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()
        let density = Float(currentRendering.effectIntensity)
            * WallpaperSceneEffectsPolicy.densityMultiplier(for: currentProfile)
        cell.contents = Self.particleImage(for: effect)
        cell.lifetimeRange = 3
        cell.spinRange = .pi
        cell.alphaSpeed = -0.025

        switch effect {
        case .none:
            cell.birthRate = 0
        case .dust:
            cell.birthRate = 5 * density
            cell.lifetime = 18
            cell.velocity = 4
            cell.velocityRange = 7
            cell.emissionRange = .pi * 2
            cell.scale = 0.18
            cell.scaleRange = 0.11
            cell.alphaRange = 0.22
        case .snow:
            cell.birthRate = 13 * density
            cell.lifetime = 16
            cell.velocity = 34
            cell.velocityRange = 13
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = .pi / 9
            cell.yAcceleration = -2
            cell.xAcceleration = 1.5
            cell.scale = 0.24
            cell.scaleRange = 0.14
            cell.alphaRange = 0.16
        case .embers:
            cell.birthRate = 8 * density
            cell.lifetime = 8
            cell.velocity = 42
            cell.velocityRange = 18
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 6
            cell.yAcceleration = 5
            cell.scale = 0.16
            cell.scaleRange = 0.1
            cell.alphaSpeed = -0.09
            cell.color = NSColor.systemOrange.cgColor
        }
        return cell
    }

    private func layoutEmitterLayer() {
        guard let emitterLayer else { return }
        emitterLayer.frame = bounds
        switch currentRendering.ambientEffect {
        case .none:
            break
        case .dust:
            emitterLayer.emitterShape = .rectangle
            emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            emitterLayer.emitterSize = bounds.size
        case .snow:
            emitterLayer.emitterShape = .line
            emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY)
            emitterLayer.emitterSize = CGSize(width: bounds.width, height: 1)
        case .embers:
            emitterLayer.emitterShape = .line
            emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY)
            emitterLayer.emitterSize = CGSize(width: bounds.width * 0.82, height: 1)
        }
    }

    private func updateMusicReaction() {
        musicGlowLayer.removeAnimation(forKey: Motion.musicGlowAnimationKey)
        emitterLayer?.removeAnimation(forKey: Motion.particlePulseAnimationKey)
        musicGlowLayer.opacity = 0

        guard isComposerLayerRenderable(.musicGlow),
              WallpaperMusicReactionPolicy.shouldAnimate(
            reaction: currentRendering.musicReaction,
            isPlaying: currentMediaPlayback.isPlaying,
            profile: currentProfile,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            paused: isPaused
        ) else { return }

        let profileMultiplier = WallpaperMusicReactionPolicy.intensityMultiplier(
            for: currentProfile
        )
        let intensity = Float(currentRendering.musicReactionIntensity) * profileMultiplier
        let accent = NSColor(
            calibratedRed: currentMediaPlayback.accentRed,
            green: currentMediaPlayback.accentGreen,
            blue: currentMediaPlayback.accentBlue,
            alpha: 1
        )
        musicGlowLayer.colors = [
            accent.withAlphaComponent(0.76).cgColor,
            accent.withAlphaComponent(0.18).cgColor,
            NSColor.clear.cgColor,
        ]

        let lowOpacity = 0.05 + (0.06 * intensity)
        let highOpacity = 0.14 + (0.28 * intensity)
        musicGlowLayer.opacity = lowOpacity

        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = lowOpacity
        glow.toValue = highOpacity
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        switch currentRendering.musicReaction {
        case .none:
            return
        case .ambientGlow:
            glow.duration = 2.8
        case .playbackPulse:
            glow.duration = 1.25
            if let emitterLayer {
                let particles = CABasicAnimation(keyPath: "birthRate")
                particles.fromValue = 0.72
                particles.toValue = 1.18 + (0.22 * intensity)
                particles.duration = 1.25
                particles.autoreverses = true
                particles.repeatCount = .infinity
                particles.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                emitterLayer.add(particles, forKey: Motion.particlePulseAnimationKey)
            }
        }
        musicGlowLayer.add(glow, forKey: Motion.musicGlowAnimationKey)
    }

    private func updateParallaxSubscription() {
        let shouldTrack = isComposerLayerRenderable(.media)
            && WallpaperSceneEffectsPolicy.shouldTrackPointer(
            strength: currentRendering.parallaxStrength,
            profile: currentProfile,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            paused: isPaused
        )
        guard shouldTrack else {
            removePointerSubscription()
            resetParallax(animated: true)
            return
        }
        if pointerSubscriptionID != nil {
            updateParallax(mouseLocation: NSEvent.mouseLocation)
            return
        }
        pointerSubscriptionID = WallpaperPointerMonitor.shared.subscribe { [weak self] location in
            self?.updateParallax(mouseLocation: location)
        }
        updateParallax(mouseLocation: NSEvent.mouseLocation)
    }

    private func removePointerSubscription() {
        guard let pointerSubscriptionID else { return }
        WallpaperPointerMonitor.shared.unsubscribe(pointerSubscriptionID)
        self.pointerSubscriptionID = nil
    }

    private func updateParallax(mouseLocation: CGPoint) {
        guard let screenFrame = window?.screen?.frame, screenFrame.width > 0, screenFrame.height > 0 else {
            return
        }
        let normalizedX = min(max((mouseLocation.x - screenFrame.midX) / (screenFrame.width / 2), -1), 1)
        let normalizedY = min(max((mouseLocation.y - screenFrame.midY) / (screenFrame.height / 2), -1), 1)
        let strength = CGFloat(currentRendering.parallaxStrength)
        let maximumOffset = 14 * strength
        let scale = 1 + (0.025 * strength)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(
            x: normalizedX * maximumOffset,
            y: normalizedY * maximumOffset
        )
        transform = transform.scaledBy(x: scale, y: scale)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        mediaMotionLayer.setAffineTransform(transform)
        CATransaction.commit()
    }

    private func resetParallax(animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.18 : 0)
        mediaMotionLayer.setAffineTransform(.identity)
        CATransaction.commit()
    }

    private static func particleImage(
        for effect: WallpaperSceneRenderingConfiguration.AmbientEffect
    ) -> CGImage? {
        let size = 12
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let color: NSColor = effect == .embers ? .systemOrange : .white
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: 2, y: 2, width: 8, height: 8))
        return context.makeImage()
    }
}

@MainActor
private final class WallpaperPointerMonitor {
    static let shared = WallpaperPointerMonitor()

    private enum Timing {
        static let minimumDispatchInterval: TimeInterval = 1.0 / 30.0
    }

    private var subscribers: [UUID: (CGPoint) -> Void] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastDispatchTime: TimeInterval = 0

    func subscribe(_ handler: @escaping (CGPoint) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        installMonitorsIfNeeded()
        return id
    }

    func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
        guard subscribers.isEmpty else { return }
        removeMonitors()
    }

    private func installMonitorsIfNeeded() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in self?.publishCurrentLocation() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.publishCurrentLocation()
            return event
        }
    }

    private func publishCurrentLocation() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDispatchTime >= Timing.minimumDispatchInterval else { return }
        lastDispatchTime = now
        let location = NSEvent.mouseLocation
        for handler in subscribers.values {
            handler(location)
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        lastDispatchTime = 0
    }
}

nonisolated enum WallpaperSceneEffectsPolicy {
    static func shouldRender(
        effect: WallpaperSceneRenderingConfiguration.AmbientEffect,
        profile: WallpaperPerformanceProfile,
        reduceMotion: Bool,
        paused: Bool
    ) -> Bool {
        effect != .none
            && densityMultiplier(for: profile) > 0
            && !reduceMotion
            && !paused
    }

    static func shouldTrackPointer(
        strength: Double,
        profile: WallpaperPerformanceProfile,
        reduceMotion: Bool,
        paused: Bool
    ) -> Bool {
        strength > 0.001 && profile != .eco && !reduceMotion && !paused
    }

    static func densityMultiplier(for profile: WallpaperPerformanceProfile) -> Float {
        switch profile {
        case .eco: 0.22
        case .automatic, .balanced: 0.62
        case .cinematic: 1
        }
    }

    static func blurMultiplier(for profile: WallpaperPerformanceProfile) -> Double {
        switch profile {
        case .eco: 0.25
        case .automatic, .balanced: 0.65
        case .cinematic: 1
        }
    }

    static func maximumAnimatedLayers(for profile: WallpaperPerformanceProfile) -> Int {
        switch profile {
        case .eco: 1
        case .automatic, .balanced: 2
        case .cinematic: 5
        }
    }

    static func animationAmountMultiplier(
        for profile: WallpaperPerformanceProfile
    ) -> Double {
        switch profile {
        case .eco: 0.45
        case .automatic, .balanced: 0.72
        case .cinematic: 1
        }
    }
}

nonisolated enum WallpaperMusicReactionPolicy {
    static func shouldAnimate(
        reaction: WallpaperSceneRenderingConfiguration.MusicReaction,
        isPlaying: Bool,
        profile: WallpaperPerformanceProfile,
        reduceMotion: Bool,
        paused: Bool
    ) -> Bool {
        reaction != .none
            && isPlaying
            && intensityMultiplier(for: profile) > 0
            && !reduceMotion
            && !paused
    }

    static func intensityMultiplier(for profile: WallpaperPerformanceProfile) -> Float {
        switch profile {
        case .eco: 0.34
        case .automatic, .balanced: 0.72
        case .cinematic: 1
        }
    }
}

nonisolated enum WallpaperSceneMotionPolicy {
    static func shouldAnimate(
        preset: WallpaperSceneRenderingConfiguration.MotionPreset,
        kind: WallpaperScene.Kind?,
        profile: WallpaperPerformanceProfile,
        reduceMotion: Bool,
        paused: Bool
    ) -> Bool {
        preset != .none
            && kind == .image
            && profile != .eco
            && !reduceMotion
            && !paused
    }
}

private extension WallpaperSceneRenderingConfiguration.ScalingMode {
    var contentsGravity: CALayerContentsGravity {
        switch self {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        case .stretch: .resize
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        case .stretch: .resize
        }
    }
}
