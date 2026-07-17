//
//  MacFlowHomeView.swift
//  MacFlow
//
//  Responsive command centre with one clear layer of workspace status.
//

import SwiftUI

struct MacFlowHomeView: View {
    @Binding var selection: MacFlowSection

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var scenes: WallpaperSceneController
    @EnvironmentObject private var mouseFree: MouseFreeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("macflow.profile.displayName") private var profileName = ""

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 280), spacing: MacFlowSpacing.space12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(eyebrow: "Workspace", title: "Home")
            Divider().overlay(MacFlowColor.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space24) {
                    welcome

                    VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                        MacFlowSectionHeader("Your workspaces")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: MacFlowSpacing.space12) {
                            workspaceCard(
                                .notch,
                                status: settings.showNotch ? "Active" : "Off",
                                value: notchDetail,
                                isActive: settings.showNotch
                            )
                            workspaceCard(
                                .mouseFree,
                                status: mouseFree.status.title,
                                value: mouseFree.selectedPreset?.title ?? "Custom",
                                isActive: mouseFree.status == .active
                            )
                            workspaceCard(
                                .wallpaperEngine,
                                status: scenes.isRunning ? "Live" : "Ready",
                                value: scenes.activeScene?.title ?? "\(scenes.library.scenes.count) scenes",
                                isActive: scenes.isRunning
                            )
                        }
                    }

                    quickActions

                    if mouseFree.status == .needsAccessibility {
                        permissionAlert
                            .transition(AppMotion.transition(reduceMotion: reduceMotion))
                    }

                    activeFlow
                }
                .padding(MacFlowSpacing.space24)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Quick actions")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MacFlowSpacing.space8) { quickActionButtons }
                VStack(spacing: MacFlowSpacing.space8) { quickActionButtons }
            }
        }
    }

    @ViewBuilder
    private var quickActionButtons: some View {
        Button {
            settings.showNotch.toggle()
            NotchHaptics.perform(.confirmation)
        } label: {
            Label(settings.showNotch ? "Hide Notch" : "Show Notch", systemImage: "macbook")
        }
        .buttonStyle(.bordered)

        Button { navigate(to: .wallpaperEngine) } label: {
            Label("Change Wallpaper", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(.borderedProminent)

        Button { navigate(to: .mouseFree) } label: {
            Label("Tune Scrolling", systemImage: "computermouse")
        }
        .buttonStyle(.bordered)
    }

    private var permissionAlert: some View {
        HStack(spacing: MacFlowSpacing.space12) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("MouseFree needs Accessibility")
                    .font(.callout.weight(.medium))
                Text("Review the permission once from the installed MacFlow app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review") { navigate(to: .mouseFree) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(MacFlowSpacing.space12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                .stroke(.orange.opacity(0.22), lineWidth: 1)
        }
    }

    private var welcome: some View {
        HStack(spacing: MacFlowSpacing.space16) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                Text(greeting)
                    .font(.title2.weight(.semibold))
                Text("Everything important, in one rhythm.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: MacFlowSpacing.space16)
            Label(activeModuleSummary, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, MacFlowSpacing.space12)
                .frame(height: 30)
                .background(.green.opacity(0.08), in: Capsule())
        }
        .padding(MacFlowSpacing.space16)
        .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.panel, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
    }

    private func workspaceCard(
        _ section: MacFlowSection,
        status: String,
        value: String,
        isActive: Bool
    ) -> some View {
        Button { navigate(to: section) } label: {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space16) {
                HStack {
                    Image(systemName: section.systemImage)
                        .font(.headline)
                        .foregroundStyle(section.accent)
                        .frame(width: 32, height: 32)
                        .background(section.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                    Circle()
                        .fill(isActive ? Color.green : MacFlowColor.textTertiary)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(isActive ? "Active" : "Inactive")
                }

                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text(section.title).font(.headline)
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(value)
                }

                HStack {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isActive ? .green : .secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(MacFlowSpacing.space16)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacFlowRadius.panel, style: .continuous)
                    .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MacFlowModuleButtonStyle(reduceMotion: reduceMotion))
        .accessibilityHint("Open \(section.title)")
    }

    private var activeFlow: some View {
        HStack(spacing: MacFlowSpacing.space12) {
            Image(systemName: scenes.activeScene == nil ? "waveform.path.ecg" : "photo.fill")
                .foregroundStyle(scenes.activeScene == nil ? MacFlowColor.accent : MacFlowColor.wallpaper)
                .frame(width: 30, height: 30)
                .background(MacFlowColor.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(scenes.activeScene?.title ?? "MacFlow is ready")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(scenes.activeScene == nil ? "Choose a workspace to begin" : "Active wallpaper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if scenes.activeScene != nil {
                Button("Open Wallpapers") { navigate(to: .wallpaperEngine) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(MacFlowSpacing.space12)
        .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
    }

    private var greeting: String {
        let firstName = profileName.split(separator: " ").first.map(String.init)
        return firstName.map { "Welcome, \($0)" } ?? "Welcome to MacFlow"
    }

    private var activeModuleSummary: String {
        let count = [settings.showNotch, mouseFree.status == .active, scenes.isRunning].filter { $0 }.count
        return "\(count) active"
    }

    private var notchDetail: String {
        "\(settings.notchContentSize.title) · \([settings.fileShelfEnabled, settings.airDropEnabled, settings.liveActivitiesEnabled].filter { $0 }.count) features"
    }

    private func navigate(to section: MacFlowSection) {
        NotchHaptics.perform(.navigation)
        withAnimation(AppMotion.interaction(reduceMotion: reduceMotion)) { selection = section }
    }
}

private struct MacFlowModuleButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.992 : 1)
            .animation(.easeOut(duration: AppMotion.Duration.instant), value: configuration.isPressed)
    }
}
