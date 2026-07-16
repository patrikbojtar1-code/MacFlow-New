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
                title: "Home",
                subtitle: "Monitor and open every MacFlow workspace."
            ) {
                HStack(spacing: MacFlowSpacing.space8) {
                    Button {
                        navigate(to: .mouseFree)
                    } label: {
                        Label("Tune MouseFree", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        navigate(to: .wallpaperEngine)
                    } label: {
                        Label("Open Wallpapers", systemImage: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MacFlowColor.accent)
                }
            }

            Divider().overlay(MacFlowColor.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space24) {
                    commandStrip

                    HStack(alignment: .top, spacing: MacFlowSpacing.space12) {
                        runtimeOverview
                            .frame(maxWidth: .infinity)
                        quickControls
                            .frame(width: 300)
                    }
                }
                .padding(MacFlowSpacing.space24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var commandStrip: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Workspaces", detail: "Open a module or inspect its live state")

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
            VStack(alignment: .leading, spacing: MacFlowSpacing.space16) {
                HStack {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(section.accent)
                        .frame(width: 34, height: 34)
                        .background(section.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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

                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text(section.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(MacFlowColor.textSecondary)
                        .lineLimit(1)
                }

                HStack {
                    Text(section.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacFlowColor.textTertiary)
                        .lineLimit(2)
                    Spacer(minLength: MacFlowSpacing.space8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacFlowColor.textSecondary)
                }
            }
            .padding(MacFlowSpacing.space16)
            .frame(maxWidth: .infinity, minHeight: 162, alignment: .topLeading)
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
            MacFlowSectionHeader("Live overview", detail: "Current state from the shared runtime")
            MacFlowSettingsGroup {
                runtimeRow(
                    icon: "macbook",
                    tint: MacFlowColor.notch,
                    title: "Notch runtime",
                    detail: settings.showNotch ? "Listening for media, calls and activities" : "Notch workspace is paused",
                    value: settings.showNotch ? "Live" : "Off",
                    isActive: settings.showNotch
                )
                MacFlowInsetDivider()
                runtimeRow(
                    icon: "computermouse.fill",
                    tint: MacFlowColor.mouseFree,
                    title: "Scroll profile",
                    detail: mouseFree.isAccessibilityTrusted ? "External wheel interception available" : "Accessibility permission required",
                    value: mouseFree.selectedPreset?.title ?? "Custom",
                    isActive: mouseFree.status == .active
                )
                MacFlowInsetDivider()
                runtimeRow(
                    icon: "photo.on.rectangle.angled",
                    tint: MacFlowColor.wallpaper,
                    title: "Wallpaper engine",
                    detail: scenes.activeScene?.title ?? "No scene is currently applied",
                    value: scenes.isRunning ? "Live" : "Ready",
                    isActive: scenes.isRunning
                )
            }
        }
    }

    private func runtimeRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        value: String,
        isActive: Bool
    ) -> some View {
        MacFlowSettingsRow(icon: icon, tint: tint, title: title, subtitle: detail) {
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

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Quick controls")
            MacFlowSettingsGroup {
                quickToggle(
                    icon: "macbook",
                    title: "Notch",
                    tint: MacFlowColor.notch,
                    binding: $settings.showNotch
                )
                MacFlowInsetDivider()
                quickToggle(
                    icon: "computermouse.fill",
                    title: "MouseFree",
                    tint: MacFlowColor.mouseFree,
                    binding: $mouseFree.isEnabled
                )
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "photo.stack.fill",
                    tint: MacFlowColor.wallpaper,
                    title: scenes.activeScene == nil ? "Choose a scene" : "Open current scene",
                    subtitle: scenes.activeScene?.title ?? "Browse your local wallpaper library"
                ) {
                    Button {
                        navigate(to: .wallpaperEngine)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacFlowColor.textSecondary)
                    .accessibilityLabel("Open Wallpapers")
                }
            }
        }
    }

    private func quickToggle(
        icon: String,
        title: String,
        tint: Color,
        binding: Binding<Bool>
    ) -> some View {
        MacFlowSettingsRow(icon: icon, tint: tint, title: title) {
            Toggle(title, isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var notchDetail: String {
        let enabledFeatures = [settings.fileShelfEnabled, settings.airDropEnabled, settings.liveActivitiesEnabled]
            .filter { $0 }
            .count
        return "\(enabledFeatures) core features enabled"
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
