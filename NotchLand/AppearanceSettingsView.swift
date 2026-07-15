//
//  AppearanceSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.theme) {
                    ForEach(NotchSettings.Theme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Material") {
                Toggle("Use Blur Material Background", isOn: $settings.useBlurMaterial)
            }

            Section("Notch Content") {
                Picker("Notch content size", selection: $settings.notchContentSize) {
                    ForEach(NotchSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Virtual notch on external displays", isOn: $settings.virtualNotchEnabled)

                Text("Small stays compact. Medium adds context. Large opens the complete attached surface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview("Appearance Settings") {
    NotchPreviewContainer {
        AppearanceSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
