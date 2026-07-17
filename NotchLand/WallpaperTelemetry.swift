//
//  WallpaperTelemetry.swift
//  MacFlow
//
//  Event-driven wallpaper diagnostics. This intentionally measures the current
//  renderer before later phases change playback policy or session ownership.
//

import AVFoundation
import Combine
import CoreMedia
import Foundation
import ImageIO

nonisolated enum WallpaperDisplayVisibilityState: Equatable, Sendable {
    case visible
    case partiallyVisible(fraction: Double)
    case covered
    case fullscreenCovered
    case sleeping
    case disconnected

    var title: String {
        switch self {
        case .visible: "Visible"
        case .partiallyVisible(let fraction):
            "Partially visible (\(Int((min(max(fraction, 0), 1) * 100).rounded()))%)"
        case .covered: "Covered"
        case .fullscreenCovered: "Fullscreen covered"
        case .sleeping: "Sleeping"
        case .disconnected: "Disconnected"
        }
    }
}

nonisolated enum WallpaperPauseReason: String, Equatable, Sendable {
    case user
    case sessionInactive
    case fullscreen
    case thermalPressure
    case covered
    case displaySleeping

    var title: String {
        switch self {
        case .user: "Paused by user"
        case .sessionInactive: "Session inactive"
        case .fullscreen: "Fullscreen application"
        case .thermalPressure: "Thermal pressure"
        case .covered: "Desktop covered"
        case .displaySleeping: "Display sleeping"
        }
    }
}

nonisolated enum WallpaperThermalLevel: String, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}

nonisolated enum WallpaperRendererReadiness: String, Equatable, Sendable {
    case preparing
    case itemReady
    case likelyToKeepUp
    case firstFramePresented
    case failed
}

nonisolated enum WallpaperTransitionStrategy: String, Equatable, Sendable {
    case direct
    case dualRendererCrossfade
    case reducedMotionSwap
    case unknown
}

nonisolated enum WallpaperTransitionPhase: String, Equatable, Sendable {
    case preparing
    case animating
    case completed
    case cancelled
}

nonisolated struct WallpaperAssetDiagnostics: Equatable, Sendable {
    let sceneID: UUID
    let kind: WallpaperScene.Kind
    let codec: String?
    let resolution: CGSize?
    let nominalFramesPerSecond: Double?
    let estimatedBitrate: Int?
    let duration: TimeInterval?
    let variantName: String
}

nonisolated struct WallpaperDisplayTelemetry: Identifiable, Equatable, Sendable {
    let id: UInt32
    var visibility: WallpaperDisplayVisibilityState
    var rendererCount: Int
    var playerCount: Int
    var readiness: WallpaperRendererReadiness?
    var isPaused: Bool
    var pauseReason: WallpaperPauseReason?
    var droppedFrames: Int?
    var timeToFirstFrame: TimeInterval?
}

nonisolated struct WallpaperTransitionTelemetry: Identifiable, Equatable, Sendable {
    let id: UUID
    let sceneID: UUID
    let strategy: WallpaperTransitionStrategy
    let targetDisplayIDs: [UInt32]
    let startedAt: Date
    var firstFrameAt: Date?
    var animationStartedAt: Date?
    var completedAt: Date?
    var phase: WallpaperTransitionPhase
    var cancellationReason: String?

    var timeToFirstFrame: TimeInterval? {
        firstFrameAt.map { $0.timeIntervalSince(startedAt) }
    }

    var animationDuration: TimeInterval? {
        guard let animationStartedAt, let completedAt else { return nil }
        return completedAt.timeIntervalSince(animationStartedAt)
    }

    var totalDuration: TimeInterval? {
        completedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

nonisolated struct WallpaperTelemetrySnapshot: Equatable, Sendable {
    var updatedAt: Date
    var sceneID: UUID?
    var sceneTitle: String?
    var asset: WallpaperAssetDiagnostics?
    var playbackRate: Double?
    var selectedProfile: WallpaperPerformanceProfile?
    var effectiveProfile: WallpaperPerformanceProfile?
    var isLowPowerModeEnabled: Bool
    var thermalLevel: WallpaperThermalLevel
    var isPaused: Bool
    var pauseReason: WallpaperPauseReason?
    var displays: [WallpaperDisplayTelemetry]
    var activeRendererCount: Int
    var activePlayerCount: Int
    var droppedFrames: Int?
    var estimatedDecodedMemoryBytes: Int64?
    var currentTransition: WallpaperTransitionTelemetry?
    var lastTransition: WallpaperTransitionTelemetry?

    static let empty = WallpaperTelemetrySnapshot(
        updatedAt: .now,
        sceneID: nil,
        sceneTitle: nil,
        asset: nil,
        playbackRate: nil,
        selectedProfile: nil,
        effectiveProfile: nil,
        isLowPowerModeEnabled: false,
        thermalLevel: .nominal,
        isPaused: false,
        pauseReason: nil,
        displays: [],
        activeRendererCount: 0,
        activePlayerCount: 0,
        droppedFrames: nil,
        estimatedDecodedMemoryBytes: nil,
        currentTransition: nil,
        lastTransition: nil
    )
}

nonisolated struct WallpaperTelemetryEvent: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case sceneSelected
        case rendererCreated
        case itemReady
        case likelyToKeepUp
        case firstFrame
        case accessLog
        case rendererFailed
        case rendererStopped
        case transitionStarted
        case transitionAnimating
        case transitionCompleted
        case transitionCancelled
        case playbackChanged
        case displayChanged
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    let detail: String
    let displayID: UInt32?
    let transitionID: UUID?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        kind: Kind,
        detail: String,
        displayID: UInt32? = nil,
        transitionID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.detail = detail
        self.displayID = displayID
        self.transitionID = transitionID
    }
}

nonisolated enum WallpaperRendererEvent: Equatable, Sendable {
    case rendererCreated(hasPlayer: Bool)
    case playerItemReady
    case playbackLikelyToKeepUp
    case firstFramePresented
    case accessLog(droppedFrames: Int, observedBitrate: Int?)
    case failed(String)
    case stopped
}

private nonisolated struct WallpaperRendererTelemetryRecord: Equatable, Sendable {
    let id: UUID
    let displayID: UInt32
    let transitionID: UUID?
    let hasPlayer: Bool
    var readiness: WallpaperRendererReadiness
    var isPaused: Bool
    var pauseReason: WallpaperPauseReason?
    var droppedFrames: Int?
    var timeToFirstFrame: TimeInterval?
}

@MainActor
final class WallpaperTelemetryMonitor: ObservableObject {
    @Published private(set) var snapshot = WallpaperTelemetrySnapshot.empty
    @Published private(set) var recentEvents: [WallpaperTelemetryEvent] = []

    let benchmarkRunner = WallpaperBenchmarkRunner()

    private let maximumEventCount: Int
    private let inspectsAssetMetadata: Bool
    private var renderers: [UUID: WallpaperRendererTelemetryRecord] = [:]
    private var connectedDisplayIDs = Set<UInt32>()
    private var visibilityByDisplayID: [UInt32: WallpaperDisplayVisibilityState] = [:]
    private var assetTask: Task<Void, Never>?

    init(maximumEventCount: Int = 96, inspectsAssetMetadata: Bool = true) {
        self.maximumEventCount = max(16, maximumEventCount)
        self.inspectsAssetMetadata = inspectsAssetMetadata
    }

    deinit {
        assetTask?.cancel()
    }

    func updateContext(
        scene: WallpaperScene,
        assetURL: URL,
        displayIDs: Set<UInt32>,
        selectedProfile: WallpaperPerformanceProfile,
        effectiveProfile: WallpaperPerformanceProfile,
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState,
        isPaused: Bool,
        pauseReason: WallpaperPauseReason?,
        at timestamp: Date = .now
    ) {
        let sceneChanged = snapshot.sceneID != scene.id
        snapshot.sceneID = scene.id
        snapshot.sceneTitle = scene.title
        snapshot.playbackRate = scene.rendering.playbackRate
        snapshot.selectedProfile = selectedProfile
        snapshot.effectiveProfile = effectiveProfile
        snapshot.isLowPowerModeEnabled = isLowPowerModeEnabled
        snapshot.thermalLevel = WallpaperThermalLevel(thermalState)
        snapshot.isPaused = isPaused
        snapshot.pauseReason = pauseReason
        synchronizeDisplays(displayIDs, at: timestamp)
        updateRendererPauseState(isPaused: isPaused, reason: pauseReason)

        if sceneChanged || snapshot.asset?.sceneID != scene.id {
            snapshot.asset = nil
            appendEvent(.init(
                timestamp: timestamp,
                kind: .sceneSelected,
                detail: "\(scene.title) · \(scene.kind.displayName)"
            ))
            if inspectsAssetMetadata {
                inspectAsset(scene: scene, url: assetURL)
            }
        }
        publish(at: timestamp)
    }

    func synchronizeDisplays(_ displayIDs: Set<UInt32>, at timestamp: Date = .now) {
        let disconnected = connectedDisplayIDs.subtracting(displayIDs)
        let connected = displayIDs.subtracting(connectedDisplayIDs)
        connectedDisplayIDs = displayIDs

        for displayID in connected {
            visibilityByDisplayID[displayID] = .visible
            appendEvent(.init(
                timestamp: timestamp,
                kind: .displayChanged,
                detail: "Display connected",
                displayID: displayID
            ))
        }
        for displayID in disconnected {
            visibilityByDisplayID[displayID] = .disconnected
            appendEvent(.init(
                timestamp: timestamp,
                kind: .displayChanged,
                detail: "Display disconnected",
                displayID: displayID
            ))
        }
        publish(at: timestamp)
    }

    func updateVisibility(
        _ visibility: WallpaperDisplayVisibilityState,
        displayID: UInt32,
        at timestamp: Date = .now
    ) {
        guard visibilityByDisplayID[displayID] != visibility else { return }
        visibilityByDisplayID[displayID] = visibility
        appendEvent(.init(
            timestamp: timestamp,
            kind: .displayChanged,
            detail: visibility.title,
            displayID: displayID
        ))
        publish(at: timestamp)
    }

    func updatePlayback(
        isPaused: Bool,
        reason: WallpaperPauseReason?,
        at timestamp: Date = .now
    ) {
        guard snapshot.isPaused != isPaused || snapshot.pauseReason != reason else { return }
        snapshot.isPaused = isPaused
        snapshot.pauseReason = reason
        updateRendererPauseState(isPaused: isPaused, reason: reason)
        appendEvent(.init(
            timestamp: timestamp,
            kind: .playbackChanged,
            detail: isPaused ? (reason?.title ?? "Paused") : "Playing"
        ))
        publish(at: timestamp)
    }

    func deactivate(at timestamp: Date = .now) {
        assetTask?.cancel()
        assetTask = nil
        if let transition = snapshot.currentTransition {
            cancelTransition(
                id: transition.id,
                reason: "Wallpaper runtime deactivated",
                at: timestamp
            )
        }
        snapshot.sceneID = nil
        snapshot.sceneTitle = nil
        snapshot.asset = nil
        snapshot.playbackRate = nil
        snapshot.isPaused = true
        snapshot.pauseReason = .user
        publish(at: timestamp)
    }

    func beginTransition(
        id: UUID,
        sceneID: UUID,
        targetDisplayIDs: Set<UInt32>,
        strategy: WallpaperTransitionStrategy,
        at timestamp: Date = .now
    ) {
        if let active = snapshot.currentTransition,
           active.phase == .preparing || active.phase == .animating {
            cancelTransition(id: active.id, reason: "Superseded by a newer scene", at: timestamp)
        }
        snapshot.currentTransition = WallpaperTransitionTelemetry(
            id: id,
            sceneID: sceneID,
            strategy: strategy,
            targetDisplayIDs: targetDisplayIDs.sorted(),
            startedAt: timestamp,
            firstFrameAt: nil,
            animationStartedAt: nil,
            completedAt: nil,
            phase: .preparing,
            cancellationReason: nil
        )
        appendEvent(.init(
            timestamp: timestamp,
            kind: .transitionStarted,
            detail: "\(strategy.rawValue) · \(targetDisplayIDs.count) display(s)",
            transitionID: id
        ))
        publish(at: timestamp)
    }

    func rendererEvent(
        _ event: WallpaperRendererEvent,
        rendererID: UUID,
        displayID: UInt32,
        transitionID: UUID?,
        at timestamp: Date = .now
    ) {
        switch event {
        case .rendererCreated(let hasPlayer):
            renderers[rendererID] = WallpaperRendererTelemetryRecord(
                id: rendererID,
                displayID: displayID,
                transitionID: transitionID,
                hasPlayer: hasPlayer,
                readiness: .preparing,
                isPaused: snapshot.isPaused,
                pauseReason: snapshot.pauseReason,
                droppedFrames: nil,
                timeToFirstFrame: nil
            )
            appendEvent(.init(
                timestamp: timestamp,
                kind: .rendererCreated,
                detail: hasPlayer ? "Video player created" : "Still renderer created",
                displayID: displayID,
                transitionID: transitionID
            ))

        case .playerItemReady:
            updateRenderer(rendererID) { $0.readiness = .itemReady }
            appendEvent(.init(
                timestamp: timestamp,
                kind: .itemReady,
                detail: "AVPlayerItem ready",
                displayID: displayID,
                transitionID: transitionID
            ))

        case .playbackLikelyToKeepUp:
            updateRenderer(rendererID) { $0.readiness = .likelyToKeepUp }
            appendEvent(.init(
                timestamp: timestamp,
                kind: .likelyToKeepUp,
                detail: "Playback likely to keep up",
                displayID: displayID,
                transitionID: transitionID
            ))

        case .firstFramePresented:
            let firstFrameDuration: TimeInterval?
            if let transitionID,
               let transition = snapshot.currentTransition,
               transition.id == transitionID {
                firstFrameDuration = timestamp.timeIntervalSince(transition.startedAt)
            } else {
                firstFrameDuration = nil
            }
            updateRenderer(rendererID) {
                $0.readiness = .firstFramePresented
                $0.timeToFirstFrame = firstFrameDuration
            }
            updateFirstFrameMilestone(transitionID: transitionID, at: timestamp)
            appendEvent(.init(
                timestamp: timestamp,
                kind: .firstFrame,
                detail: firstFrameDuration.map { "First frame in \(Self.milliseconds($0)) ms" }
                    ?? "First frame presented",
                displayID: displayID,
                transitionID: transitionID
            ))

        case .accessLog(let droppedFrames, _):
            updateRenderer(rendererID) { $0.droppedFrames = droppedFrames }
            appendEvent(.init(
                timestamp: timestamp,
                kind: .accessLog,
                detail: "Dropped frames: \(droppedFrames)",
                displayID: displayID,
                transitionID: transitionID
            ))

        case .failed(let reason):
            updateRenderer(rendererID) { $0.readiness = .failed }
            appendEvent(.init(
                timestamp: timestamp,
                kind: .rendererFailed,
                detail: reason,
                displayID: displayID,
                transitionID: transitionID
            ))

        case .stopped:
            renderers.removeValue(forKey: rendererID)
            appendEvent(.init(
                timestamp: timestamp,
                kind: .rendererStopped,
                detail: "Renderer released",
                displayID: displayID,
                transitionID: transitionID
            ))
        }
        publish(at: timestamp)
    }

    func transitionAnimationStarted(id: UUID, at timestamp: Date = .now) {
        guard snapshot.currentTransition?.id == id else { return }
        snapshot.currentTransition?.animationStartedAt = timestamp
        snapshot.currentTransition?.phase = .animating
        appendEvent(.init(
            timestamp: timestamp,
            kind: .transitionAnimating,
            detail: "Crossfade animation started",
            transitionID: id
        ))
        publish(at: timestamp)
    }

    func completeTransition(id: UUID, at timestamp: Date = .now) {
        guard snapshot.currentTransition?.id == id else { return }
        snapshot.currentTransition?.completedAt = timestamp
        snapshot.currentTransition?.phase = .completed
        snapshot.lastTransition = snapshot.currentTransition
        snapshot.currentTransition = nil
        appendEvent(.init(
            timestamp: timestamp,
            kind: .transitionCompleted,
            detail: snapshot.lastTransition?.totalDuration.map {
                "Completed in \(Self.milliseconds($0)) ms"
            } ?? "Completed",
            transitionID: id
        ))
        publish(at: timestamp)
    }

    func cancelTransition(id: UUID, reason: String, at timestamp: Date = .now) {
        guard snapshot.currentTransition?.id == id else { return }
        snapshot.currentTransition?.completedAt = timestamp
        snapshot.currentTransition?.phase = .cancelled
        snapshot.currentTransition?.cancellationReason = reason
        snapshot.lastTransition = snapshot.currentTransition
        snapshot.currentTransition = nil
        appendEvent(.init(
            timestamp: timestamp,
            kind: .transitionCancelled,
            detail: reason,
            transitionID: id
        ))
        publish(at: timestamp)
    }

    func reset(at timestamp: Date = .now) {
        assetTask?.cancel()
        assetTask = nil
        renderers.removeAll()
        connectedDisplayIDs.removeAll()
        visibilityByDisplayID.removeAll()
        snapshot = .empty
        snapshot.updatedAt = timestamp
        recentEvents.removeAll()
        benchmarkRunner.cancel()
    }

    private func inspectAsset(scene: WallpaperScene, url: URL) {
        assetTask?.cancel()
        assetTask = Task { @MainActor [weak self] in
            let diagnostics = await WallpaperAssetDiagnosticsReader.inspect(scene: scene, url: url)
            guard let self, !Task.isCancelled, self.snapshot.sceneID == scene.id else { return }
            self.snapshot.asset = diagnostics
            self.publish(at: .now)
        }
    }

    private func updateRendererPauseState(isPaused: Bool, reason: WallpaperPauseReason?) {
        for id in renderers.keys {
            renderers[id]?.isPaused = isPaused
            renderers[id]?.pauseReason = reason
        }
    }

    private func updateRenderer(
        _ id: UUID,
        update: (inout WallpaperRendererTelemetryRecord) -> Void
    ) {
        guard var renderer = renderers[id] else { return }
        update(&renderer)
        renderers[id] = renderer
    }

    private func updateFirstFrameMilestone(transitionID: UUID?, at timestamp: Date) {
        guard let transitionID,
              snapshot.currentTransition?.id == transitionID,
              snapshot.currentTransition?.firstFrameAt == nil else { return }
        let targets = Set(snapshot.currentTransition?.targetDisplayIDs ?? [])
        let readyDisplays = Set(renderers.values.compactMap { renderer in
            renderer.transitionID == transitionID
                && renderer.readiness == .firstFramePresented
                ? renderer.displayID
                : nil
        })
        guard targets.isSubset(of: readyDisplays) else { return }
        snapshot.currentTransition?.firstFrameAt = timestamp

        if snapshot.currentTransition?.strategy == .direct {
            completeTransition(id: transitionID, at: timestamp)
        }
    }

    private func appendEvent(_ event: WallpaperTelemetryEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maximumEventCount {
            recentEvents.removeLast(recentEvents.count - maximumEventCount)
        }
    }

    private func publish(at timestamp: Date) {
        snapshot.updatedAt = timestamp
        let grouped = Dictionary(grouping: renderers.values, by: \.displayID)
        let knownDisplayIDs = connectedDisplayIDs.union(visibilityByDisplayID.keys)
        snapshot.displays = knownDisplayIDs.sorted().map { displayID in
            let displayRenderers = grouped[displayID] ?? []
            let mostReady = displayRenderers.max { lhs, rhs in
                Self.readinessRank(lhs.readiness) < Self.readinessRank(rhs.readiness)
            }
            return WallpaperDisplayTelemetry(
                id: displayID,
                visibility: visibilityByDisplayID[displayID] ?? .visible,
                rendererCount: displayRenderers.count,
                playerCount: displayRenderers.filter(\.hasPlayer).count,
                readiness: mostReady?.readiness,
                isPaused: displayRenderers.first?.isPaused ?? snapshot.isPaused,
                pauseReason: displayRenderers.first?.pauseReason ?? snapshot.pauseReason,
                droppedFrames: displayRenderers.compactMap(\.droppedFrames).max(),
                timeToFirstFrame: displayRenderers.compactMap(\.timeToFirstFrame).max()
            )
        }
        snapshot.activeRendererCount = renderers.count
        snapshot.activePlayerCount = renderers.values.filter(\.hasPlayer).count
        let droppedFrameCounts = renderers.values.compactMap(\.droppedFrames)
        snapshot.droppedFrames = droppedFrameCounts.isEmpty
            ? nil
            : droppedFrameCounts.reduce(0, +)
        snapshot.estimatedDecodedMemoryBytes = estimatedDecodedMemoryBytes()
        benchmarkRunner.observe(snapshot)
    }

    private func estimatedDecodedMemoryBytes() -> Int64? {
        guard let size = snapshot.asset?.resolution,
              size.width > 0, size.height > 0,
              !renderers.isEmpty else { return nil }
        let pixels = Int64(size.width.rounded(.up)) * Int64(size.height.rounded(.up))
        let buffersPerRenderer: Int64 = snapshot.asset?.kind == .video ? 3 : 1
        return pixels * 4 * buffersPerRenderer * Int64(renderers.count)
    }

    private static func readinessRank(_ readiness: WallpaperRendererReadiness) -> Int {
        switch readiness {
        case .preparing: 0
        case .itemReady: 1
        case .likelyToKeepUp: 2
        case .firstFramePresented: 3
        case .failed: -1
        }
    }

    private static func milliseconds(_ duration: TimeInterval) -> String {
        String(format: "%.0f", duration * 1_000)
    }
}

nonisolated enum WallpaperAssetDiagnosticsReader {
    static func inspect(scene: WallpaperScene, url: URL) async -> WallpaperAssetDiagnostics {
        switch scene.kind {
        case .image:
            let resolution = await Task.detached(priority: .utility) {
                imageResolution(at: url)
            }.value
            return WallpaperAssetDiagnostics(
                sceneID: scene.id,
                kind: scene.kind,
                codec: url.pathExtension.uppercased(),
                resolution: resolution,
                nominalFramesPerSecond: nil,
                estimatedBitrate: nil,
                duration: nil,
                variantName: "Original"
            )
        case .video:
            return await inspectVideo(scene: scene, url: url)
        }
    }

    private static func inspectVideo(scene: WallpaperScene, url: URL) async -> WallpaperAssetDiagnostics {
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return unavailable(scene: scene)
            }
            async let naturalSize = track.load(.naturalSize)
            async let preferredTransform = track.load(.preferredTransform)
            async let nominalFrameRate = track.load(.nominalFrameRate)
            async let estimatedDataRate = track.load(.estimatedDataRate)
            async let formatDescriptions = track.load(.formatDescriptions)
            async let duration = asset.load(.duration)

            let loadedNaturalSize = try await naturalSize
            let loadedTransform = try await preferredTransform
            let transformed = loadedNaturalSize.applying(loadedTransform)
            let loadedFormatDescriptions = try await formatDescriptions
            let formatDescription = loadedFormatDescriptions.first
            let codec = formatDescription.map {
                fourCharacterCode(CMFormatDescriptionGetMediaSubType($0))
            }
            let fps = Double(try await nominalFrameRate)
            let bitrate = Int((try await estimatedDataRate).rounded())
            let loadedDuration = try await duration
            let assetDuration = loadedDuration.seconds
            return WallpaperAssetDiagnostics(
                sceneID: scene.id,
                kind: scene.kind,
                codec: codec,
                resolution: CGSize(width: abs(transformed.width), height: abs(transformed.height)),
                nominalFramesPerSecond: fps > 0 ? fps : nil,
                estimatedBitrate: bitrate > 0 ? bitrate : nil,
                duration: assetDuration.isFinite ? assetDuration : nil,
                variantName: "Original"
            )
        } catch {
            return unavailable(scene: scene)
        }
    }

    private static func unavailable(scene: WallpaperScene) -> WallpaperAssetDiagnostics {
        WallpaperAssetDiagnostics(
            sceneID: scene.id,
            kind: scene.kind,
            codec: nil,
            resolution: nil,
            nominalFramesPerSecond: nil,
            estimatedBitrate: nil,
            duration: nil,
            variantName: "Original"
        )
    }

    private static func imageResolution(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? String(code)
    }
}
