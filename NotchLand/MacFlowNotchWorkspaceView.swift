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
                title: "Notch"
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
                        .font(.system(size: 10.5, weight: tab == item ? .medium : .regular))
                        .foregroundStyle(tab == item ? .primary : MacFlowColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MacFlowSpacing.space8)
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
        .padding(.horizontal, MacFlowSpacing.space20)
        .padding(.bottom, MacFlowSpacing.space12)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: MacFlowSpacing.space12) {
                        hardwarePreview.frame(maxWidth: .infinity)
                        runtimePanel.frame(width: 242)
                    }
                    VStack(spacing: MacFlowSpacing.space12) {
                        hardwarePreview
                        runtimePanel
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: MacFlowSpacing.space12) {
                        coreControls.frame(maxWidth: .infinity)
                        integrations.frame(maxWidth: .infinity)
                    }
                    VStack(spacing: MacFlowSpacing.space12) {
                        coreControls
                        integrations
                    }
                }
            }
            .padding(MacFlowSpacing.space20)
        }
        .scrollIndicators(.hidden)
    }

    private var hardwarePreview: some View {
        MacFlowPanel(.elevated) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                MacFlowSectionHeader("Preview") {
                    Text(settings.notchContentSize.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacFlowColor.textSecondary)
                }
                GeometryReader { proxy in
                    let shellWidth = min(max(330, proxy.size.width - 28), 460)
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                            .fill(Color.white.opacity(0.025))

                        NotchShape(
                            topWidth: min(previewNotchWidth, shellWidth * 0.42),
                            bottomCornerRadius: 17,
                            shoulderRadius: 13
                        )
                        .fill(.black)
                        .frame(width: shellWidth, height: 58)
                        .overlay {
                            HStack(spacing: 0) {
                                HStack(spacing: MacFlowSpacing.space8) {
                                    Circle()
                                        .fill(settings.liveActivitiesEnabled ? MacFlowColor.notch : MacFlowColor.textTertiary)
                                        .frame(width: 7, height: 7)
                                    Text(settings.liveActivitiesEnabled ? "Activity" : "Ready")
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Color.clear
                                    .frame(width: min(previewNotchWidth, shellWidth * 0.42))
                                    .accessibilityHidden(true)

                                HStack(spacing: MacFlowSpacing.space8) {
                                    Image(systemName: "waveform")
                                    Image(systemName: "pause.fill")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MacFlowColor.notch)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.horizontal, MacFlowSpacing.space16)
                            .padding(.top, 29)
                            .padding(.bottom, MacFlowSpacing.space8)
                        }
                    }
                }
                .frame(height: 82)
            }
            .padding(MacFlowSpacing.space12)
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
        .frame(height: 42)
    }

    private var coreControls: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Core behavior")
            MacFlowSettingsGroup {
                settingToggle(
                    icon: "cursorarrow.motionlines",
                    title: "Hover to expand",
                    binding: $settings.hoverToExpand
                )
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "rectangle.3.group",
                    tint: MacFlowColor.notch,
                    title: "Content size",
                    subtitle: nil
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
                    binding: $settings.fileShelfEnabled
                )
                MacFlowInsetDivider()
                settingToggle(
                    icon: "airplayaudio",
                    title: "AirDrop",
                    binding: $settings.airDropEnabled
                )
                MacFlowInsetDivider()
                settingToggle(
                    icon: "phone.fill",
                    title: "Call detection",
                    binding: $settings.systemCallDetectionEnabled
                )
            }
        }
    }

    private func settingToggle(
        icon: String,
        title: String,
        binding: Binding<Bool>
    ) -> some View {
        MacFlowSettingsRow(icon: icon, tint: MacFlowColor.notch, title: title) {
            Toggle(title, isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var previewNotchWidth: CGFloat {
        switch settings.notchContentSize {
        case .small: 136
        case .medium: 154
        case .large: 174
        }
    }
}
