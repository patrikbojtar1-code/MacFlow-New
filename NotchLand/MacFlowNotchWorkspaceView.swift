//
//  MacFlowNotchWorkspaceView.swift
//  MacFlow
//
//  Structured workspace for notch runtime and feature configuration.
//

import AppKit
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
    @Namespace private var tabSelectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(
                eyebrow: "Notch workspace",
                title: "Notch"
            ) {
                HStack(spacing: MacFlowSpacing.space12) {
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
            .animation(AppMotion.stateChange(reduceMotion: reduceMotion), value: tab)
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
                        .background {
                            if tab == item {
                                RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                                    .fill(MacFlowColor.surface2)
                                    .matchedGeometryEffect(id: "notch-tab-surface", in: tabSelectionNamespace)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if tab == item {
                                Capsule()
                                    .fill(MacFlowColor.notch)
                                    .frame(width: 34, height: 2)
                                    .offset(y: 1)
                                    .matchedGeometryEffect(id: "notch-tab-indicator", in: tabSelectionNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(AppMotion.interaction(reduceMotion: reduceMotion), value: tab)
        .padding(MacFlowSpacing.space4)
        .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
        .padding(.horizontal, MacFlowSpacing.space24)
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
            .padding(MacFlowSpacing.space24)
            .frame(maxWidth: MacFlowMetrics.readableContentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .top)
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
                RealNotchMediaPreview(size: settings.notchContentSize)
                    .frame(height: 112)
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

}

private struct RealNotchMediaPreview: View {
    let size: NotchSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    private let hardwareWidth: CGFloat = 184
    private let invertedRadius = FloatingNotchView.musicInvertedRadius

    var body: some View {
        GeometryReader { proxy in
            let bodyWidth = presentation.preferredWidth + NowPlayingMetrics.widthAddition(for: size)
            let outerWidth = bodyWidth + invertedRadius * 2
            let height = NowPlayingMetrics.compactHeight(for: size)
            let availableWidth = max(1, proxy.size.width - MacFlowSpacing.space16)
            let previewScale = min(1, availableWidth / outerWidth)
            let shape = NotchDropShape(
                invertedCornerRadius: invertedRadius,
                bottomCornerRadius: NotchLayoutMetrics.bottomRadius(for: size)
            )

            ZStack(alignment: .bottom) {
                shape.fill(.black)
                CompactMediaContent(
                    presentation: presentation,
                    processedBackground: Self.previewBackground,
                    backgroundIdentity: "macflow-notch-preview",
                    hardwareNotchWidth: hardwareWidth,
                    notchSize: size,
                    isHovering: false,
                    revealsContent: true,
                    accessibilityContrast: accessibilityContrast,
                    reduceMotion: reduceMotion,
                    onPlayPause: {}
                )
                .frame(width: bodyWidth, height: height)
            }
            .frame(width: outerWidth, height: height)
            .clipShape(shape)
            .scaleEffect(previewScale, anchor: .center)
            .frame(width: outerWidth * previewScale, height: height * previewScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(AppMotion.emphasized(reduceMotion: reduceMotion), value: size)
        }
        .background(
            MacFlowColor.canvas,
            in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Real notch media preview")
        .accessibilityValue("\(size.title) content size")
    }

    private var presentation: NowPlayingService.CompactMediaPresentation {
        NowPlayingService.Track(
            title: "A Dios Le Pido",
            artist: "Juanes",
            album: nil,
            artwork: nil,
            duration: 213,
            elapsedAtTimestamp: 48,
            timestamp: .now,
            playbackRate: 1,
            sourceApplicationName: "Spotify",
            sourceBundleIdentifier: "com.spotify.client"
        ).compactPresentation
    }

    private static let previewBackground: NSImage = {
        let image = NSImage(size: NSSize(width: 240, height: 96))
        image.lockFocus()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.12, green: 0.46, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.07, alpha: 1),
        ])?.draw(in: NSRect(origin: .zero, size: image.size), angle: 0)
        image.unlockFocus()
        return image
    }()
}
