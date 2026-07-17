//
//  WallpaperSceneWindow.swift
//  NotchLand
//
//  A mouse-transparent desktop renderer for a single display.
//

import AppKit
import AVFoundation
import ImageIO
import QuartzCore

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
private final class WallpaperSceneRenderView: NSView {
    private enum Motion {
        static let treatmentDuration: CFTimeInterval = 0.18
    }

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoLayer: AVPlayerLayer?
    private var imageLayer: CALayer?
    private var currentAssetURL: URL?
    private var currentKind: WallpaperScene.Kind?
    private var imageLoadTask: Task<Void, Never>?
    private var currentRendering = WallpaperSceneRenderingConfiguration.default
    private let dimmingLayer = CALayer()
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
        dimmingLayer.backgroundColor = NSColor.black.cgColor
        dimmingLayer.opacity = 0
        layer?.addSublayer(dimmingLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        imageLayer?.frame = bounds
        videoLayer?.frame = bounds
        dimmingLayer.frame = bounds
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
    }

    func update(rendering: WallpaperSceneRenderingConfiguration) {
        update(rendering: rendering, animated: true)
    }

    func setPaused(_ paused: Bool) {
        guard let player else { return }
        if paused {
            player.pause()
        } else if player.timeControlStatus != .playing {
            player.playImmediately(atRate: Float(currentRendering.playbackRate))
        }
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
            self.layer?.insertSublayer(imageLayer, below: self.dimmingLayer)
            self.imageLayer = imageLayer
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
        layer?.insertSublayer(videoLayer, below: dimmingLayer)

        self.player = player
        self.looper = looper
        self.videoLayer = videoLayer
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

        CATransaction.begin()
        CATransaction.setAnimationDuration(
            animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? Motion.treatmentDuration
                : 0
        )
        imageLayer?.contentsGravity = normalized.scalingMode.contentsGravity
        videoLayer?.videoGravity = normalized.scalingMode.videoGravity
        dimmingLayer.opacity = Float(normalized.dimming)
        CATransaction.commit()

        guard let player else { return }
        player.defaultRate = Float(normalized.playbackRate)
        if player.timeControlStatus == .playing {
            player.playImmediately(atRate: Float(normalized.playbackRate))
        }
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
