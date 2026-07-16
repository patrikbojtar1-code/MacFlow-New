//
//  WallpaperSceneWindow.swift
//  NotchLand
//
//  A mouse-transparent desktop renderer for a single display.
//

import AppKit
import AVFoundation
import QuartzCore

@MainActor
final class WallpaperSceneWindow: NSWindow {
    private let rendererView = WallpaperSceneRenderView()

    init(screen: NSScreen) {
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
        paused: Bool
    ) {
        rendererView.display(scene: scene, assetURL: assetURL, profile: profile)
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
        rendererView.stop()
        orderOut(nil)
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
    private var currentRendering = WallpaperSceneRenderingConfiguration.default
    private let dimmingLayer = CALayer()

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
        profile: WallpaperPerformanceProfile
    ) {
        if currentAssetURL == assetURL, currentKind == scene.kind {
            update(profile: profile)
            update(rendering: scene.rendering)
            return
        }

        stop()
        currentAssetURL = assetURL
        currentKind = scene.kind
        currentRendering = scene.rendering.normalized

        switch scene.kind {
        case .image:
            displayImage(at: assetURL)
        case .video:
            displayVideo(at: assetURL, profile: profile)
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
    }

    private func displayImage(at url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return
        }

        let imageLayer = CALayer()
        imageLayer.contents = cgImage
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        imageLayer.frame = bounds
        layer?.insertSublayer(imageLayer, below: dimmingLayer)
        self.imageLayer = imageLayer
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
        update(profile: profile)
        player.playImmediately(atRate: Float(currentRendering.playbackRate))
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
