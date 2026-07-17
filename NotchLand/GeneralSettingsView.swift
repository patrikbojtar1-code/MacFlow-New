//
//  GeneralSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var focusMode: FocusModeController

    var body: some View {
        Form {
            Section {
                Toggle("Show MacFlow", isOn: $settings.showNotch)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            Section("Features") {
                Toggle("File Shelf", isOn: $settings.fileShelfEnabled)
                Text("Drop files onto the notch to keep them available between apps and relaunches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("AirDrop", isOn: $settings.airDropEnabled)
                Text("Send files from the shelf with AirDrop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Focus") {
                LabeledContent("Focus Detection") {
                    Text(focusDetectionLabel)
                        .foregroundStyle(focusDetectionColor)
                }

                LabeledContent("Current Focus") {
                    Text(focusMode.isFocusActive ? "On" : "Off")
                        .foregroundStyle(focusMode.isFocusActive ? .blue : .secondary)
                }

                Button("Restart Focus Monitor") {
                    focusMode.stop()
                    focusMode.start()
                }
            }

            Section("Welcome Experience") {
                Button("Replay Onboarding") {
                    settings.hasCompletedOnboarding = false
                }
                Text("Reopens the guided setup. Your files, wallet addresses and module configuration remain untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var focusDetectionLabel: String {
        switch focusMode.authorizationStatus {
        case .monitoring: "Listening"
        case .stopped: "Stopped"
        }
    }

    private var focusDetectionColor: Color {
        switch focusMode.authorizationStatus {
        case .monitoring: .green
        case .stopped: .secondary
        }
    }
}

#if DEBUG
#Preview("General Settings") {
    NotchPreviewContainer {
        GeneralSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
