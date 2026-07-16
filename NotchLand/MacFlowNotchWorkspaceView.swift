//
//  MacFlowNotchWorkspaceView.swift
//  MacFlow
//
//  Structured workspace for notch runtime and feature configuration.
//

import SwiftUI

struct MacFlowNotchWorkspaceView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview
        case widgets
        case calendar
        case wallet
        case behavior
        case appearance

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var focusMode: FocusModeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: Tab = .overview

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(
                eyebrow: "Notch workspace",
                title: "Notch",
                subtitle: "Configure what appears around the physical MacBook notch."
            ) {
                HStack(spacing: MacFlowSpacing.space10) {
                    Text(settings.showNotch ? "Enabled" : "Paused")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(settings.showNotch ? .green : MacFlowColor.textSecondary)
                    Toggle("Enable Notch", isOn: $settings.showNotch)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            notchTabBar
            Divider().overlay(MacFlowColor.borderSubtle)

            Group {
                switch tab {
                case .overview:
                    overview
                case .widgets:
                    WidgetSettingsView()
                case .calendar:
                    CalendarSettingsView()
                case .wallet:
                    WalletSettingsView()
                case .behavior:
                    BehaviorSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(tab)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 5)))
            .animation(MacFlowMotion.content(reduceMotion: reduceMotion), value: tab)
        }
    }

    private var notchTabBar: some View {
        HStack(spacing: MacFlowSpacing.space4) {
            ForEach(Tab.allCases) { item in
                Button {
                    NotchHaptics.perform(.navigation)
                    tab = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: tab == item ? .medium : .regular))
                        .foregroundStyle(tab == item ? .primary : MacFlowColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MacFlowSpacing.space10)
                        .background(
                            tab == item ? MacFlowColor.surface2 : .clear,
                            in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                        )
                        .overlay(alignment: .bottom) {
                            if tab == item {
                                Capsule()
                                    .fill(MacFlowColor.notch)
                                    .frame(width: 34, height: 2)
                                    .offset(y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MacFlowSpacing.space4)
        .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
        .padding(.horizontal, MacFlowSpacing.space24)
        .padding(.bottom, MacFlowSpacing.space16)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space20) {
                HStack(alignment: .top, spacing: MacFlowSpacing.space12) {
                    hardwarePreview
                        .frame(maxWidth: .infinity)
                    runtimePanel
                        .frame(width: 300)
                }

                HStack(alignment: .top, spacing: MacFlowSpacing.space12) {
                    coreControls.frame(maxWidth: .infinity)
                    integrations.frame(maxWidth: .infinity)
                }
            }
            .padding(MacFlowSpacing.space24)
        }
        .scrollIndicators(.hidden)
    }

    private var hardwarePreview: some View {
        MacFlowPanel(.elevated) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space16) {
                MacFlowSectionHeader("Hardware preview", detail: settings.notchContentSize.title)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: MacFlowRadius.preview, style: .continuous)
                        .fill(Color.black.opacity(0.92))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.black)
                        .frame(width: previewNotchWidth, height: 27)
                    HStack {
                        HStack(spacing: MacFlowSpacing.space8) {
                            Circle().fill(MacFlowColor.notch).frame(width: 8, height: 8)
                            Text(settings.liveActivitiesEnabled ? "Live activities" : "Notch ready")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        Spacer()
                        Image(systemName: "waveform")
                            .foregroundStyle(MacFlowColor.notch)
                    }
                    .padding(.horizontal, MacFlowSpacing.space20)
                    .padding(.top, 43)
                }
                .frame(height: 112)

                HStack(spacing: MacFlowSpacing.space16) {
                    Label("Top anchored", systemImage: "pin.fill")
                    Label("\(settings.notchContentSize.title) content", systemImage: "rectangle.expand.vertical")
                    Label(settings.hoverToExpand ? "Hover enabled" : "Click only", systemImage: "cursorarrow.motionlines")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(MacFlowColor.textSecondary)
            }
            .padding(MacFlowSpacing.space16)
        }
    }

    private var runtimePanel: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Runtime")
            MacFlowSettingsGroup {
                runtimeRow("Workspace", value: settings.showNotch ? "Active" : "Paused", active: settings.showNotch)
                MacFlowInsetDivider(leading: MacFlowSpacing.space16)
                runtimeRow("Focus monitor", value: focusMode.isFocusActive ? "Focused" : "Listening", active: focusMode.authorizationStatus == .monitoring)
                MacFlowInsetDivider(leading: MacFlowSpacing.space16)
                runtimeRow("Live activities", value: settings.liveActivitiesEnabled ? "Enabled" : "Disabled", active: settings.liveActivitiesEnabled)
            }
        }
    }

    private func runtimeRow(_ title: String, value: String, active: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(MacFlowColor.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
            Circle()
                .fill(active ? Color.green : MacFlowColor.textTertiary)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, MacFlowSpacing.space16)
        .frame(height: 48)
    }

    private var coreControls: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Core behavior")
            MacFlowSettingsGroup {
                settingToggle(
                    icon: "cursorarrow.motionlines",
                    title: "Hover to expand",
                    detail: "Preview content when the pointer reaches the notch.",
                    binding: $settings.hoverToExpand
                )
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "rectangle.3.group",
                    tint: MacFlowColor.notch,
                    title: "Content size",
                    subtitle: "Shared compact density for notch activities."
                ) {
                    Picker("Content size", selection: $settings.notchContentSize) {
                        ForEach(NotchSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                MacFlowInsetDivider()
                settingToggle(
                    icon: "bolt.horizontal.fill",
                    title: "Live activities",
                    detail: "Show contextual status updates around the notch.",
                    binding: $settings.liveActivitiesEnabled
                )
            }
        }
    }

    private var integrations: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Integrations")
            MacFlowSettingsGroup {
                settingToggle(
                    icon: "folder.fill",
                    title: "File Shelf",
                    detail: "Keep dropped files available between apps.",
                    binding: $settings.fileShelfEnabled
                )
                MacFlowInsetDivider()
                settingToggle(
                    icon: "airplayaudio",
                    title: "AirDrop",
                    detail: "Send shelf files through the native share flow.",
                    binding: $settings.airDropEnabled
                )
                MacFlowInsetDivider()
                settingToggle(
                    icon: "phone.fill",
                    title: "Call detection",
                    detail: "Present supported incoming and active calls.",
                    binding: $settings.systemCallDetectionEnabled
                )
            }
        }
    }

    private func settingToggle(
        icon: String,
        title: String,
        detail: String,
        binding: Binding<Bool>
    ) -> some View {
        MacFlowSettingsRow(icon: icon, tint: MacFlowColor.notch, title: title, subtitle: detail) {
            Toggle(title, isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var previewNotchWidth: CGFloat {
        switch settings.notchContentSize {
        case .small: 78
        case .medium: 104
        case .large: 132
        }
    }
}
