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
    @StateObject private var motionDebugger = MotionDebugStore.shared

    var body: some View {
        Form {
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
                }
            }

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
