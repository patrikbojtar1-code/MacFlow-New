//
//  DebugSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Debug test surface. Compiled out unless NOTCHLAND_ENABLE_DEBUG_UI is
//  explicitly added to Swift Active Compilation Conditions.
//
//

#if NOTCHLAND_ENABLE_DEBUG_UI

import SwiftUI

struct DebugSettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hud: HUDController
    @EnvironmentObject var batteryAlerts: BatteryAlertController
    @EnvironmentObject var focusMode: FocusModeController
    @EnvironmentObject var screenLock: ScreenLockController
    @EnvironmentObject var countdown: EventCountdownController
    @EnvironmentObject var airDrop: AirDropController
    @EnvironmentObject var liveActivities: LiveActivityController
    @EnvironmentObject var notchTimer: NotchTimerController
    @EnvironmentObject var calls: CallActivityController
    @EnvironmentObject var displayCoordinator: DisplayCoordinator
    @EnvironmentObject var scenes: WallpaperSceneController
    @StateObject private var motionDebugger = MotionDebugStore.shared

    var body: some View {
        Form {
            Section("Runtime") {
                LabeledContent("Notch state") {
                    Text(appState.isExpanded ? "Expanded" : (appState.isHovering ? "Hover" : "Compact"))
                }
                LabeledContent("Content size") {
                    Text(settings.notchContentSize.title)
                }
                LabeledContent("Display policy") {
                    Text(settings.displayPolicy.title)
                }

                ForEach(displayCoordinator.displays) { display in
                    VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                        HStack {
                            Label(
                                display.name,
                                systemImage: display.isBuiltIn ? "laptopcomputer" : "display"
                            )
                            Spacer()
                            Text("\(display.scaleFactor, format: .number)×")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Text(
                            "ID \(display.id) · "
                                + "\(Int(display.frame.width))×\(Int(display.frame.height)) · "
                                + "x \(Int(display.frame.minX)), y \(Int(display.frame.minY))"
                        )
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }
                }
            }

            Section("Motion Debugger") {
                Toggle("Record named motion", isOn: $motionDebugger.isEnabled)
                    .accessibilityHint("Records animation state, reason and redraw count in Debug builds only")

                if motionDebugger.isEnabled {
                    HStack(spacing: MacFlowSpacing.space16) {
                        Label(
                            "\(motionDebugger.activeEvents.count) active",
                            systemImage: motionDebugger.activeEvents.count > 1
                                ? "exclamationmark.triangle.fill"
                                : "waveform.path"
                        )
                        .foregroundStyle(motionDebugger.activeEvents.count > 1 ? .orange : .secondary)

                        Spacer()

                        Button("Clear") { motionDebugger.clear() }
                            .disabled(motionDebugger.events.isEmpty)
                    }

                    if motionDebugger.events.isEmpty {
                        ContentUnavailableView(
                            "No motion recorded",
                            systemImage: "waveform.path",
                            description: Text("Interact with the notch, change its size, or switch a module.")
                        )
                    } else {
                        ForEach(motionDebugger.events.prefix(12)) { event in
                            MotionDebugEventRow(event: event)
                        }
                    }

                    if !motionDebugger.renderCounts.isEmpty {
                        DisclosureGroup("Render activity") {
                            ForEach(
                                motionDebugger.renderCounts.keys.sorted(),
                                id: \.self
                            ) { surface in
                                LabeledContent(surface) {
                                    Text("\(motionDebugger.renderCounts[surface, default: 0]) updates")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            WallpaperTelemetryDebugSection(telemetry: scenes.telemetry)

            Section("Factory") {
                Button(role: .destructive) {
                    resetToFactory()
                } label: {
                    Label("Reset to Factory", systemImage: "arrow.counterclockwise.circle.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.bordered)
            }

            Section("Battery") {
                HStack {
                    testButton("Charging", systemImage: "bolt.fill") {
                        showNotchIfNeeded()
                        batteryAlerts.debugShowCharging(percent: 50)
                    }

                    testButton("Charging 100%", systemImage: "bolt.fill") {
                        showNotchIfNeeded()
                        batteryAlerts.debugShowCharging(percent: 100)
                    }
                }

                HStack {
                    testButton("Low 20%", systemImage: "exclamationmark.circle.fill") {
                        showNotchIfNeeded()
                        batteryAlerts.debugShowLowBattery(percent: 20)
                    }

                    testButton("Low 10%", systemImage: "exclamationmark.triangle.fill") {
                        showNotchIfNeeded()
                        batteryAlerts.debugShowLowBattery(percent: 10)
                    }
                }
            }

            Section("Focus") {
                HStack {
                    testButton("Focus On", systemImage: "moon.fill") {
                        showNotchIfNeeded()
                        focusMode.debugShowFocusOn()
                    }
                }
            }

            Section("Calls") {
                testButton("Incoming", systemImage: "phone.arrow.down.left") {
                    showNotchIfNeeded()
                    calls.showDesignPreview()
                }
            }

            Section("Screen Lock") {
                HStack {
                    testButton("Lock Flash", systemImage: "lock.fill") {
                        showNotchIfNeeded()
                        screenLock.debugShowLock()
                    }

                    testButton("Unlock", systemImage: "lock.open.fill") {
                        showNotchIfNeeded()
                        screenLock.debugShowUnlock()
                    }
                }
            }

            Section("AirDrop") {
                HStack {
                    testButton("Drop Zone", systemImage: "dot.radiowaves.left.and.right") {
                        showNotchIfNeeded()
                        airDrop.debugShowDropTarget()
                    }

                    testButton("Test Share", systemImage: "square.and.arrow.up") {
                        airDrop.shareViaAirDrop([debugShareFileURL()])
                    }

                    testButton("Close", systemImage: "xmark") {
                        airDrop.dragEnded()
                    }
                }
            }

            Section("HUD") {
                HStack {
                    testButton("Volume", systemImage: "speaker.wave.2.fill") {
                        showNotchIfNeeded()
                        hud.debugShow(.volume(level: 0.66, muted: false))
                    }

                    testButton("Muted", systemImage: "speaker.slash.fill") {
                        showNotchIfNeeded()
                        hud.debugShow(.volume(level: 0.4, muted: true))
                    }

                    testButton("Brightness", systemImage: "sun.max.fill") {
                        showNotchIfNeeded()
                        hud.debugShow(.brightness(level: 0.72))
                    }
                }

                HStack {
                    testButton("Keyboard", systemImage: "keyboard") {
                        showNotchIfNeeded()
                        hud.debugShow(.keyboardBrightness(level: 0.58))
                    }

                    testButton("Contrast", systemImage: "circle.lefthalf.filled") {
                        showNotchIfNeeded()
                        hud.debugShow(.contrast(level: 0.48))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetToFactory() {
        hud.dismissCurrent()
        batteryAlerts.dismissCurrentPresentation()
        focusMode.dismissCurrentPresentation()
        screenLock.dismissCurrentPresentation()
        airDrop.dragEnded()
        notchTimer.cancel()
        liveActivities.endAll()
        calls.dismiss()
        countdown.clearDetail()
        appState.resetToCollapsed()
        settings.resetToFactoryDefaults()
    }

    private func showNotchIfNeeded() {
        if !settings.showNotch {
            settings.showNotch = true
        }
    }

    private func debugShareFileURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotchLand-AirDrop-Test.txt")
        try? "NotchLand AirDrop test file".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func testButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(minWidth: 112)
        }
        .buttonStyle(.bordered)
    }
}

private struct WallpaperTelemetryDebugSection: View {
    @ObservedObject var telemetry: WallpaperTelemetryMonitor
    @ObservedObject var benchmark: WallpaperBenchmarkRunner

    init(telemetry: WallpaperTelemetryMonitor) {
        self.telemetry = telemetry
        benchmark = telemetry.benchmarkRunner
    }

    var body: some View {
        Section("Wallpaper Telemetry") {
            LabeledContent("Scene", value: telemetry.snapshot.sceneTitle ?? "Inactive")
            LabeledContent("Runtime") {
                Text(
                    "\(telemetry.snapshot.activePlayerCount) player(s) · "
                        + "\(telemetry.snapshot.activeRendererCount) renderer(s) · "
                        + "\(connectedDisplayCount) display(s)"
                )
                .monospacedDigit()
            }
            LabeledContent("Profile") {
                Text(profileSummary)
            }
            LabeledContent("Asset") {
                Text(assetSummary)
                    .textSelection(.enabled)
            }
            LabeledContent("Playback") {
                Text(
                    telemetry.snapshot.isPaused
                        ? (telemetry.snapshot.pauseReason?.title ?? "Paused")
                        : "Playing"
                )
            }
            if let memory = telemetry.snapshot.estimatedDecodedMemoryBytes {
                LabeledContent("Decoded memory estimate") {
                    Text(memory, format: .byteCount(style: .memory))
                        .help("Estimated frame-buffer footprint; not a measurement of total process memory")
                }
            }
            if let transition = telemetry.snapshot.currentTransition ?? telemetry.snapshot.lastTransition {
                LabeledContent("Last transition") {
                    Text(transitionSummary(transition))
                        .monospacedDigit()
                }
            }

            ForEach(telemetry.snapshot.displays) { display in
                LabeledContent("Display \(display.id)") {
                    Text(
                        "\(display.visibility.title) · "
                            + "\(display.playerCount) player(s) · "
                            + (display.readiness?.rawValue ?? "idle")
                    )
                    .monospacedDigit()
                }
            }

            HStack {
                Menu("Start benchmark") {
                    ForEach(WallpaperBenchmarkScenario.allCases) { scenario in
                        Button(scenario.title) { benchmark.begin(scenario) }
                            .help(scenario.method)
                    }
                }
                .disabled(benchmark.activeScenario != nil)

                if let activeScenario = benchmark.activeScenario {
                    Text(activeScenario.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Finish") { benchmark.finish() }
                }
            }

            if let result = benchmark.latestResult {
                Text(
                    "\(result.scenario.title): \(result.sampleCount) event samples, "
                        + "max \(result.maximumPlayerCount) players"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !telemetry.recentEvents.isEmpty {
                DisclosureGroup("Recent events") {
                    ForEach(telemetry.recentEvents.prefix(8)) { event in
                        VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                            Text(event.kind.rawValue)
                                .font(.caption.weight(.semibold))
                            Text(event.detail)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, MacFlowSpacing.space4)
                    }
                }
            }
        }
    }

    private var connectedDisplayCount: Int {
        telemetry.snapshot.displays.filter { $0.visibility != .disconnected }.count
    }

    private var profileSummary: String {
        let effective = telemetry.snapshot.effectiveProfile?.title ?? "Unknown"
        let power = telemetry.snapshot.isLowPowerModeEnabled ? "Low Power" : "Normal power"
        return "\(effective) · \(power) · \(telemetry.snapshot.thermalLevel.rawValue)"
    }

    private var assetSummary: String {
        guard let asset = telemetry.snapshot.asset else { return "Inspecting…" }
        let codec = asset.codec ?? "Unknown codec"
        let resolution = asset.resolution.map { "\(Int($0.width))×\(Int($0.height))" } ?? "Unknown size"
        let fps = asset.nominalFramesPerSecond.map {
            "\($0.formatted(.number.precision(.fractionLength(0...2)))) fps"
        } ?? "—"
        let rate = telemetry.snapshot.playbackRate.map {
            "\($0.formatted(.number.precision(.fractionLength(0...2))))×"
        } ?? "—"
        return "\(codec) · \(resolution) · \(fps) · \(rate) · \(asset.variantName)"
    }

    private func transitionSummary(_ transition: WallpaperTransitionTelemetry) -> String {
        let firstFrame = transition.timeToFirstFrame.map {
            "first frame \(Int(($0 * 1_000).rounded())) ms"
        } ?? "first frame pending"
        let total = transition.totalDuration.map {
            "total \(Int(($0 * 1_000).rounded())) ms"
        } ?? transition.phase.rawValue
        return "\(firstFrame) · \(total)"
    }
}

private struct MotionDebugEventRow: View {
    let event: MotionDebugEvent

    var body: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space8) {
            HStack(spacing: MacFlowSpacing.space8) {
                Image(systemName: phaseSymbol)
                    .foregroundStyle(phaseColor)
                    .accessibilityHidden(true)
                Text(event.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: MacFlowSpacing.space8)
                Text(event.duration, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("s")
                    .foregroundStyle(.secondary)
            }

            Text(event.state)
                .font(.caption.monospaced())
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: MacFlowSpacing.space12) {
                Label(event.surface, systemImage: "rectangle.on.rectangle")
                Label("\(event.redrawCount) redraws", systemImage: "arrow.triangle.2.circlepath")
                    .contentTransition(.numericText())
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(event.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, MacFlowSpacing.space4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(event.name), \(event.phase.rawValue), duration \(event.duration) seconds, "
                + "\(event.redrawCount) redraws, \(event.reason)"
        )
    }

    private var phaseSymbol: String {
        switch event.phase {
        case .active: "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .interrupted: "stop.circle.fill"
        }
    }

    private var phaseColor: Color {
        switch event.phase {
        case .active: .blue
        case .completed: .green
        case .interrupted: .orange
        }
    }
}

#Preview("Debug Settings") {
    NotchPreviewContainer {
        DebugSettingsView()
            .frame(width: 510, height: 580)
    }
}

#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
