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

            HStack(spacing: 0) {
                preferenceNavigation
                Divider().overlay(MacFlowColor.borderSubtle)
                ScrollView {
                    preferenceContent
                        .frame(maxWidth: 640)
                        .padding(MacFlowSpacing.space20)
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
        .padding(MacFlowSpacing.space12)
        .frame(width: 148)
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
        Text(section.title)
            .font(.system(size: 17, weight: .semibold))
    }

    private var generalPreferences: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Startup & availability")
            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "power",
                    title: "Launch at Login"
                ) { Toggle("", isOn: $settings.launchAtLogin).labelsHidden() }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "menubar.rectangle",
                    title: "Menu Bar Item"
                ) { Toggle("", isOn: $settings.showMenuBarItem).labelsHidden() }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "macbook",
                    title: "Notch Workspace"
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
                ) { Toggle("", isOn: $settings.useBlurMaterial).labelsHidden() }
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
                    title: "Focus Monitor"
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
