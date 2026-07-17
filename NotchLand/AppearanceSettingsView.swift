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
    @EnvironmentObject private var displays: DisplayCoordinator

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

                Picker("Show notch on", selection: $settings.displayPolicy) {
                    ForEach(NotchDisplayPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                if settings.displayPolicy == .selectedDisplays {
                    if displays.displays.isEmpty {
                        Text("No displays are currently available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displays.displays) { display in
                            Toggle(
                                display.name,
                                isOn: Binding(
                                    get: { settings.selectedDisplayIDs.contains(display.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            settings.selectedDisplayIDs.insert(display.id)
                                        } else {
                                            settings.selectedDisplayIDs.remove(display.id)
                                        }
                                    }
                                )
                            )
                            .help(display.isBuiltIn ? "Built-in display" : "External display")
                        }
                    }
                }

                if !displays.displays.isEmpty {
                    DisclosureGroup("Per-display layout") {
                        ForEach(displays.displays) { display in
                            VStack(alignment: .leading, spacing: MacFlowSpacing.space8) {
                                Text(display.name)
                                    .font(.headline)

                                Picker(
                                    "Content size",
                                    selection: Binding(
                                        get: { settings.contentSize(for: display.id) },
                                        set: { settings.setContentSize($0, for: display.id) }
                                    )
                                ) {
                                    ForEach(NotchSize.allCases) { size in
                                        Text(size.title).tag(size)
                                    }
                                }

                                Stepper(
                                    value: Binding(
                                        get: { Double(settings.horizontalOffset(for: display.id)) },
                                        set: { settings.setHorizontalOffset($0, for: display.id) }
                                    ),
                                    in: -240...240,
                                    step: 8
                                ) {
                                    Text("Horizontal offset: \(Int(settings.horizontalOffset(for: display.id))) pt")
                                }
                            }
                            .padding(.vertical, MacFlowSpacing.space4)
                        }
                    }
                }

                Text("Small stays compact. Medium adds context. Large opens the complete attached surface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("notch.appearance.form")
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
