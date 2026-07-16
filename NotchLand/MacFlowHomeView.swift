//
//  MacFlowHomeView.swift
//  MacFlow
//
//  Dense command center backed entirely by live module state.
//

import SwiftUI

struct MacFlowHomeView: View {
    @Binding var selection: MacFlowSection

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var scenes: WallpaperSceneController
    @EnvironmentObject private var mouseFree: MouseFreeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(
                eyebrow: "Command center",
                title: "Home"
            )

            Divider().overlay(MacFlowColor.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space20) {
                    commandStrip
                    runtimeOverview
                }
                .padding(MacFlowSpacing.space20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var commandStrip: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Workspaces")

            HStack(spacing: MacFlowSpacing.space12) {
                moduleButton(
                    section: .notch,
                    status: settings.showNotch ? "Active" : "Paused",
                    detail: notchDetail,
                    isActive: settings.showNotch
                )
                moduleButton(
                    section: .mouseFree,
                    status: mouseFree.status.title,
                    detail: mouseFree.selectedPreset?.title ?? "Custom response",
                    isActive: mouseFree.status == .active
                )
                moduleButton(
                    section: .wallpaperEngine,
                    status: scenes.isRunning ? "Live" : "Ready",
                    detail: scenes.activeScene?.title ?? "\(scenes.library.scenes.count) scenes",
                    isActive: scenes.isRunning
                )
            }
        }
    }

    private func moduleButton(
        section: MacFlowSection,
        status: String,
        detail: String,
        isActive: Bool
    ) -> some View {
        Button {
            navigate(to: section)
        } label: {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                HStack {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(section.accent)
                        .frame(width: 30, height: 30)
                        .background(section.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    HStack(spacing: MacFlowSpacing.space6) {
                        Circle()
                            .fill(isActive ? Color.green : MacFlowColor.textTertiary)
                            .frame(width: 6, height: 6)
                        Text(status)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(isActive ? .green : MacFlowColor.textSecondary)
                    }
                }

                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacFlowColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(MacFlowSpacing.space12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacFlowRadius.panel, style: .continuous)
                    .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MacFlowModuleButtonStyle(reduceMotion: reduceMotion))
        .accessibilityHint("Opens the \(section.title) workspace")
    }

    private var runtimeOverview: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Status")
            MacFlowSettingsGroup {
                runtimeRow(
                    icon: "macbook",
                    tint: MacFlowColor.notch,
                    title: "Notch runtime",
                    value: settings.showNotch ? "Live" : "Off",
                    isActive: settings.showNotch
                )
                MacFlowInsetDivider()
                runtimeRow(
                    icon: "computermouse.fill",
                    tint: MacFlowColor.mouseFree,
                    title: "Scroll profile",
                    value: mouseFree.selectedPreset?.title ?? "Custom",
                    isActive: mouseFree.status == .active
                )
                MacFlowInsetDivider()
                runtimeRow(
                    icon: "photo.on.rectangle.angled",
                    tint: MacFlowColor.wallpaper,
                    title: "Wallpaper engine",
                    value: scenes.activeScene?.title ?? "Ready",
                    isActive: scenes.isRunning
                )
            }
        }
    }

    private func runtimeRow(
        icon: String,
        tint: Color,
        title: String,
        value: String,
        isActive: Bool
    ) -> some View {
        MacFlowSettingsRow(icon: icon, tint: tint, title: title) {
            HStack(spacing: MacFlowSpacing.space8) {
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacFlowColor.textSecondary)
                Circle()
                    .fill(isActive ? Color.green : MacFlowColor.textTertiary)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var notchDetail: String {
        let enabledFeatures = [settings.fileShelfEnabled, settings.airDropEnabled, settings.liveActivitiesEnabled]
            .filter { $0 }
            .count
        return "\(enabledFeatures) features"
    }

    private func navigate(to section: MacFlowSection) {
        NotchHaptics.perform(.navigation)
        withAnimation(MacFlowMotion.selection(reduceMotion: reduceMotion)) {
            selection = section
        }
    }
}

private struct MacFlowModuleButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? MacFlowColor.surface2 : .clear)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.992 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
