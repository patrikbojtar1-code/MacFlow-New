//
//  MacFlowPreferencesView.swift
//  MacFlow
//
//  App-level preferences. Feature-specific configuration remains in its module.
//

import SwiftUI

struct MacFlowPreferencesView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case general
        case appearance
        case updates
        case setup

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .general: "switch.2"
            case .appearance: "circle.lefthalf.filled"
            case .updates: "arrow.triangle.2.circlepath"
            case .setup: "sparkles.rectangle.stack"
            }
        }
    }

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var focusMode: FocusModeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: Section = .general

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(
                eyebrow: "Application",
                title: "Preferences",
                subtitle: "Defaults shared by every MacFlow workspace."
            )
            Divider().overlay(MacFlowColor.borderSubtle)

            HStack(spacing: 0) {
                preferenceNavigation
                Divider().overlay(MacFlowColor.borderSubtle)
                ScrollView {
                    preferenceContent
                        .frame(maxWidth: 720)
                        .padding(.horizontal, MacFlowSpacing.space32)
                        .padding(.vertical, MacFlowSpacing.space24)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.never)
            }
        }
        .animation(MacFlowMotion.content(reduceMotion: reduceMotion), value: section)
    }

    private var preferenceNavigation: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space6) {
            Text("SETTINGS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MacFlowColor.textTertiary)
                .tracking(1)
                .padding(.horizontal, MacFlowSpacing.space12)
                .padding(.bottom, MacFlowSpacing.space6)

            ForEach(Section.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: MacFlowSpacing.space10) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18)
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(section == item ? Color.white : MacFlowColor.textSecondary)
                    .padding(.horizontal, MacFlowSpacing.space12)
                    .frame(height: 36)
                    .background(
                        section == item ? MacFlowColor.surface3 : .clear,
                        in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
            Spacer()
        }
        .padding(MacFlowSpacing.space16)
        .frame(width: 176)
        .background(MacFlowColor.sidebar.opacity(0.45))
    }

    @ViewBuilder
    private var preferenceContent: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space20) {
            preferenceTitle

            switch section {
            case .general:
                generalPreferences
            case .appearance:
                appearancePreferences
            case .updates:
                updatePreferences
            case .setup:
                setupPreferences
            }
        }
        .id(section)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 5)))
    }

    private var preferenceTitle: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
            Text(section.title)
                .font(.system(size: 18, weight: .semibold))
            Text(sectionDescription)
                .font(.system(size: 11.5))
                .foregroundStyle(MacFlowColor.textSecondary)
        }
    }

    private var sectionDescription: String {
        switch section {
        case .general: "Choose how MacFlow starts and remains available."
        case .appearance: "Set the application appearance without changing module-specific visuals."
        case .updates: "Keep MacFlow current in the background or check manually."
        case .setup: "Review system integration and replay the guided setup."
        }
    }

    private var generalPreferences: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Startup & availability")
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "power",
                    title: "Launch at Login",
                    subtitle: "Start MacFlow automatically after signing in."
                ) { Toggle("", isOn: $settings.launchAtLogin).labelsHidden() }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "menubar.rectangle",
                    title: "Menu Bar Item",
                    subtitle: "Keep runtime actions available from the menu bar."
                ) { Toggle("", isOn: $settings.showMenuBarItem).labelsHidden() }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "macbook",
                    title: "Notch Workspace",
                    subtitle: "Show live activities around the hardware notch."
                ) { Toggle("", isOn: $settings.showNotch).labelsHidden() }
            }
        }
    }

    private var appearancePreferences: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Application appearance")
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "circle.lefthalf.filled",
                    title: "Color Scheme",
                    subtitle: "Follow macOS or choose a fixed appearance."
                ) {
                    Picker("Color scheme", selection: $settings.theme) {
                        ForEach(NotchSettings.Theme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "drop.halffull",
                    title: "Translucent Notch Material",
                    subtitle: "Use the macOS material treatment in the notch surface."
                ) { Toggle("", isOn: $settings.useBlurMaterial).labelsHidden() }
            }

            Text("Notch dimensions, content size and external-display behavior remain in Notch → Appearance.")
                .font(.system(size: 10.5))
                .foregroundStyle(MacFlowColor.textTertiary)
                .padding(.horizontal, MacFlowSpacing.space4)
        }
    }

    private var updatePreferences: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Software updates")
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Automatic Checks",
                    subtitle: "Periodically check for signed MacFlow releases."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.autoUpdateCheckEnabled },
                            set: { updater.setAutomaticChecks($0) }
                        )
                    )
                    .labelsHidden()
                }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "arrow.down.circle",
                    title: "Check Now",
                    subtitle: updater.canCheckForUpdates
                        ? "Ask Sparkle for the latest available release."
                        : "The update service is preparing."
                ) {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        }
    }

    private var setupPreferences: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("System integration")
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "scope",
                    title: "Focus Monitor",
                    subtitle: "Adapts MacFlow to the current macOS Focus state."
                ) {
                    HStack(spacing: MacFlowSpacing.space8) {
                        MacFlowStatusPill(
                            title: focusMode.authorizationStatus == .monitoring ? "Listening" : "Stopped",
                            systemImage: nil,
                            color: focusMode.authorizationStatus == .monitoring ? .green : .secondary
                        )
                        Button("Restart") {
                            focusMode.stop()
                            focusMode.start()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            MacFlowSectionHeader("Welcome experience")
                .padding(.top, MacFlowSpacing.space8)
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "play.rectangle.on.rectangle",
                    title: "Replay Onboarding",
                    subtitle: "Review modules and permissions without deleting your data."
                ) {
                    Button("Replay") { settings.hasCompletedOnboarding = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}
