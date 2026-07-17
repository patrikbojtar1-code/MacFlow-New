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
                title: "Preferences"
            )
            Divider().overlay(MacFlowColor.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space24) {
                    preferenceNavigation
                    preferenceContent
                }
                .frame(maxWidth: 640)
                .padding(MacFlowSpacing.space24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.never)
        }
    }

    private var preferenceNavigation: some View {
        Picker("Preference category", selection: $section) {
            ForEach(Section.allCases) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
                    .accessibilityIdentifier("preferences.section.\(item.rawValue)")
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel("Preference category")
    }

    @ViewBuilder
    private var preferenceContent: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space24) {
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
        Text(section.title)
            .font(.headline)
    }

    private var generalPreferences: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Startup & availability")
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "power",
                    title: "Launch at Login"
                ) { Toggle("Launch at Login", isOn: $settings.launchAtLogin).labelsHidden() }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "menubar.rectangle",
                    title: "Menu Bar Item"
                ) { Toggle("Menu Bar Item", isOn: $settings.showMenuBarItem).labelsHidden() }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "macbook",
                    title: "Notch Workspace"
                ) { Toggle("Notch Workspace", isOn: $settings.showNotch).labelsHidden() }
            }
        }
    }

    private var appearancePreferences: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Application appearance")
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "circle.lefthalf.filled",
                    title: "Color Scheme"
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
                    title: "Notch Material"
                ) { Toggle("Notch Material", isOn: $settings.useBlurMaterial).labelsHidden() }
            }

        }
    }

    private var updatePreferences: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Software updates")
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Automatic Checks"
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
                    title: "Check Now"
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
                    subtitle: focusMode.authorizationStatus == .monitoring
                        ? "Listening for macOS Focus changes"
                        : "Focus activities are paused"
                ) {
                    HStack(spacing: MacFlowSpacing.space8) {
                        MacFlowStatusPill(
                            title: focusMode.authorizationStatus == .monitoring ? "Listening" : "Stopped",
                            systemImage: nil,
                            color: focusMode.authorizationStatus == .monitoring ? .green : .secondary
                        )
                        Toggle(
                            "Focus Monitor",
                            isOn: Binding(
                                get: { settings.focusMonitorEnabled },
                                set: { isEnabled in
                                    settings.focusMonitorEnabled = isEnabled
                                    focusMode.setMonitoring(isEnabled)
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityIdentifier("preferences.focusMonitor")
                    }
                }
            }

            MacFlowSectionHeader("Welcome experience")
                .padding(.top, MacFlowSpacing.space8)
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "play.rectangle.on.rectangle",
                    title: "Replay Onboarding"
                ) {
                    Button("Replay") { settings.hasCompletedOnboarding = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}
