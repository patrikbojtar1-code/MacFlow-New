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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var mediaAppearanceSelection

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

            Section("Now Playing Surface") {
                HStack(spacing: MacFlowSpacing.space12) {
                    ForEach(NotchSettings.MediaAppearance.allCases) { appearance in
                        MediaAppearanceOption(
                            appearance: appearance,
                            isSelected: settings.mediaAppearance == appearance,
                            selectionNamespace: mediaAppearanceSelection
                        ) {
                            guard settings.mediaAppearance != appearance else { return }
                            NotchHaptics.perform(.navigation)
                            withAnimation(AppMotion.emphasized(reduceMotion: reduceMotion)) {
                                settings.mediaAppearance = appearance
                            }
                        }
                    }
                }
                .padding(.vertical, MacFlowSpacing.space4)

                Text(settings.mediaAppearance.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
                    .animation(
                        AppMotion.stateChange(reduceMotion: reduceMotion),
                        value: settings.mediaAppearance
                    )
            }

            Section("Notch Content") {
                Picker("Notch content size", selection: globalContentSize) {
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

    private var globalContentSize: Binding<NotchSize> {
        Binding(
            get: { settings.notchContentSize },
            set: { settings.setGlobalContentSize($0) }
        )
    }
}

private struct MediaAppearanceOption: View {
    let appearance: NotchSettings.MediaAppearance
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space8) {
                mediaSurface

                Label(appearance.label, systemImage: appearance.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(MacFlowSpacing.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MacFlowColor.surface2,
                in: RoundedRectangle(
                    cornerRadius: AppearancePreviewTokens.cardRadius,
                    style: .continuous
                )
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: AppearancePreviewTokens.cardRadius,
                        style: .continuous
                    )
                    .stroke(MacFlowColor.notch, lineWidth: AppearancePreviewTokens.selectionWidth)
                    .matchedGeometryEffect(
                        id: "media-appearance-selection",
                        in: selectionNamespace
                    )
                } else {
                    RoundedRectangle(
                        cornerRadius: AppearancePreviewTokens.cardRadius,
                        style: .continuous
                    )
                    .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance.label)
        .accessibilityValue(isSelected ? "Selected" : appearance.detail)
    }

    private var mediaSurface: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.black)

            if appearance == .ambient {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.42, blue: 0.22).opacity(0.72),
                        .black.opacity(0.92),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(Capsule(style: .continuous))
            }

            HStack(spacing: AppearancePreviewTokens.contentSpacing) {
                Circle()
                    .fill(appearance == .ambient ? Color.green : Color.white.opacity(0.78))
                    .frame(
                        width: AppearancePreviewTokens.sourceDiameter,
                        height: AppearancePreviewTokens.sourceDiameter
                    )

                Capsule()
                    .fill(.white.opacity(0.78))
                    .frame(width: AppearancePreviewTokens.titleWidth, height: 3)

                Spacer(minLength: 0)

                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appearance == .ambient ? Color.green : Color.white.opacity(0.74))
            }
            .padding(.horizontal, AppearancePreviewTokens.horizontalPadding)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.black)
                .frame(
                    width: AppearancePreviewTokens.hardwareWidth,
                    height: AppearancePreviewTokens.hardwareHeight
                )
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: AppearancePreviewTokens.surfaceHeight)
        .shadow(color: .black.opacity(0.24), radius: 5, y: 3)
    }
}

private enum AppearancePreviewTokens {
    static let cardRadius: CGFloat = 12
    static let selectionWidth: CGFloat = 1.5
    static let surfaceHeight: CGFloat = 42
    static let hardwareWidth: CGFloat = 54
    static let hardwareHeight: CGFloat = 15
    static let sourceDiameter: CGFloat = 14
    static let titleWidth: CGFloat = 32
    static let contentSpacing: CGFloat = 7
    static let horizontalPadding: CGFloat = 10
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
