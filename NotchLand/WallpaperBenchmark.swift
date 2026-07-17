//
//  WallpaperBenchmark.swift
//  MacFlow
//
//  Reproducible, event-driven benchmark definitions. CPU/GPU measurements are
//  intentionally left to Instruments; app snapshots capture runtime context.
//

import Combine
import Foundation

nonisolated enum WallpaperBenchmarkScenario: String, CaseIterable, Identifiable, Sendable {
    case h2641080pSingleDisplay
    case hevc4KSingleDisplay
    case shared4KTwoDisplays
    case distinct4KTwoDisplays
    case coveredDesktop
    case fullscreenOneDisplay
    case lowPowerMode
    case seriousThermalState
    case rapidSceneSwitching
    case displayHotPlug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h2641080pSingleDisplay: "1080p H.264 · one display"
        case .hevc4KSingleDisplay: "4K HEVC 24 fps · one display"
        case .shared4KTwoDisplays: "Same 4K scene · two displays"
        case .distinct4KTwoDisplays: "Different 4K scenes · two displays"
        case .coveredDesktop: "Covered desktop"
        case .fullscreenOneDisplay: "Fullscreen · one display"
        case .lowPowerMode: "Low Power Mode"
        case .seriousThermalState: "Serious thermal pressure"
        case .rapidSceneSwitching: "Rapid scene switching"
        case .displayHotPlug: "Display connect / disconnect"
        }
    }

    var method: String {
        switch self {
        case .h2641080pSingleDisplay:
            "Loop a local 1920×1080 H.264 asset for 60 seconds on one display."
        case .hevc4KSingleDisplay:
            "Loop a local 3840×2160 HEVC 24 fps asset for 60 seconds on one display."
        case .shared4KTwoDisplays:
            "Apply the same 4K HEVC scene to two connected displays for 60 seconds."
        case .distinct4KTwoDisplays:
            "Apply independent 4K HEVC scenes to two displays for 60 seconds."
        case .coveredDesktop:
            "Cover the desktop for 30 seconds, then reveal it and verify pause/resume."
        case .fullscreenOneDisplay:
            "Enter fullscreen on one display for 30 seconds while a second remains visible."
        case .lowPowerMode:
            "Enable Low Power Mode before a 60-second 4K playback run."
        case .seriousThermalState:
            "Use an injected policy state in tests; never attempt to heat the device intentionally."
        case .rapidSceneSwitching:
            "Select five scenes at 250 ms intervals, then wait for the final first frame."
        case .displayHotPlug:
            "Connect and disconnect one external display while a video scene is active."
        }
    }
}

nonisolated struct WallpaperBenchmarkResult: Identifiable, Equatable, Sendable {
    let id: UUID
    let scenario: WallpaperBenchmarkScenario
    let startedAt: Date
    let endedAt: Date
    let sampleCount: Int
    let maximumRendererCount: Int
    let maximumPlayerCount: Int
    let maximumDisplayCount: Int
    let maximumEstimatedDecodedMemoryBytes: Int64?
    let observedFirstFrameTimes: [TimeInterval]
    let observedTransitionDurations: [TimeInterval]
    let droppedFrames: Int?
}

@MainActor
final class WallpaperBenchmarkRunner: ObservableObject {
    @Published private(set) var activeScenario: WallpaperBenchmarkScenario?
    @Published private(set) var latestResult: WallpaperBenchmarkResult?

    private var startedAt: Date?
    private var sampleCount = 0
    private var maximumRendererCount = 0
    private var maximumPlayerCount = 0
    private var maximumDisplayCount = 0
    private var maximumEstimatedDecodedMemoryBytes: Int64?
    private var firstFrameTimes: [UUID: TimeInterval] = [:]
    private var transitionDurations: [UUID: TimeInterval] = [:]
    private var droppedFrames: Int?

    func begin(_ scenario: WallpaperBenchmarkScenario, at timestamp: Date = .now) {
        activeScenario = scenario
        startedAt = timestamp
        latestResult = nil
        sampleCount = 0
        maximumRendererCount = 0
        maximumPlayerCount = 0
        maximumDisplayCount = 0
        maximumEstimatedDecodedMemoryBytes = nil
        firstFrameTimes.removeAll()
        transitionDurations.removeAll()
        droppedFrames = nil
    }

    func observe(_ snapshot: WallpaperTelemetrySnapshot) {
        guard activeScenario != nil else { return }
        sampleCount += 1
        maximumRendererCount = max(maximumRendererCount, snapshot.activeRendererCount)
        maximumPlayerCount = max(maximumPlayerCount, snapshot.activePlayerCount)
        maximumDisplayCount = max(
            maximumDisplayCount,
            snapshot.displays.filter { $0.visibility != .disconnected }.count
        )
        if let memory = snapshot.estimatedDecodedMemoryBytes {
            maximumEstimatedDecodedMemoryBytes = max(maximumEstimatedDecodedMemoryBytes ?? 0, memory)
        }
        if let transition = snapshot.lastTransition {
            if let firstFrame = transition.timeToFirstFrame {
                firstFrameTimes[transition.id] = firstFrame
            }
            if let duration = transition.animationDuration {
                transitionDurations[transition.id] = duration
            }
        }
        if let observedDrops = snapshot.droppedFrames {
            droppedFrames = max(droppedFrames ?? 0, observedDrops)
        }
    }

    @discardableResult
    func finish(at timestamp: Date = .now) -> WallpaperBenchmarkResult? {
        guard let scenario = activeScenario, let startedAt else { return nil }
        let result = WallpaperBenchmarkResult(
            id: UUID(),
            scenario: scenario,
            startedAt: startedAt,
            endedAt: timestamp,
            sampleCount: sampleCount,
            maximumRendererCount: maximumRendererCount,
            maximumPlayerCount: maximumPlayerCount,
            maximumDisplayCount: maximumDisplayCount,
            maximumEstimatedDecodedMemoryBytes: maximumEstimatedDecodedMemoryBytes,
            observedFirstFrameTimes: firstFrameTimes.values.sorted(),
            observedTransitionDurations: transitionDurations.values.sorted(),
            droppedFrames: droppedFrames
        )
        latestResult = result
        activeScenario = nil
        self.startedAt = nil
        return result
    }

    func cancel() {
        activeScenario = nil
        startedAt = nil
    }
}
