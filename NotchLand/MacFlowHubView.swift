//
//  MacFlowHubView.swift
//  MacFlow
//
//  Premium unified shell for Notch, MouseFree, and Wallpaper Engine.
//

import SwiftUI

struct MacFlowHubView: View {
    @EnvironmentObject private var settings: NotchSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("macflow.selectedSection") private var selection: MacFlowSection = .home
    #if DEBUG
    @AppStorage("settings.debugMenuUnlocked") private var debugMenuUnlocked = false
    @State private var aboutIconTapCount = 0
    #endif

    var body: some View {
        HStack(spacing: 0) {
            MacFlowSidebarView(selection: $selection, showsDebug: showsDebug)
                .frame(width: MacFlowMetrics.sidebarWidth)

            Rectangle()
                .fill(MacFlowColor.borderSubtle)
                .frame(width: 1)

            detail
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacFlowColor.canvas)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .offset(x: 6))
                )
        }
        .background(MacFlowColor.appBackground)
        .frame(
            minWidth: MacFlowMetrics.minimumWindowWidth,
            idealWidth: MacFlowMetrics.idealWindowWidth,
            minHeight: MacFlowMetrics.minimumWindowHeight,
            idealHeight: MacFlowMetrics.idealWindowHeight
        )
        .animation(MacFlowMotion.content(reduceMotion: reduceMotion), value: selection)
        .preferredColorScheme(settings.theme.colorScheme)
    }

    private var showsDebug: Bool {
        #if DEBUG
        debugMenuUnlocked
        #else
        false
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home:
            MacFlowHomeView(selection: $selection)
        case .notch:
            MacFlowNotchModuleView()
        case .mouseFree:
            MouseFreeHubView()
        case .wallpaperEngine:
            ScenesSettingsView()
        case .preferences:
            MacFlowPreferencesView()
        case .about:
            AboutSettingsView(onIconClick: handleAboutIconClick)
        #if DEBUG
        case .debug:
            if debugMenuUnlocked {
                DebugSettingsView()
            } else {
                AboutSettingsView(onIconClick: handleAboutIconClick)
                    .onAppear { selection = .about }
            }
        #endif
        }
    }

    private func handleAboutIconClick() {
        #if DEBUG
        guard !debugMenuUnlocked else { return }
        aboutIconTapCount += 1
        if aboutIconTapCount >= 7 {
            debugMenuUnlocked = true
            selection = .debug
        }
        #endif
    }
}

private struct MacFlowBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [MacFlowTheme.ambientGlow, .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 720
            )
            LinearGradient(
                colors: [.clear, MacFlowTheme.brandViolet.opacity(0.045)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct MacFlowTopBar: View {
    let selection: MacFlowSection

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var scenes: WallpaperSceneController
    @EnvironmentObject private var mouseFree: MouseFreeController

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.eyebrow)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(selection.accent)
                    .tracking(1.15)
                Text(selection.title)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
            }

            Spacer()

            HStack(spacing: 7) {
                topStatus(systemImage: "macbook", isActive: settings.showNotch, color: .cyan)
                topStatus(systemImage: "computermouse.fill", isActive: mouseFree.status == .active, color: .orange)
                topStatus(systemImage: "photo.stack.fill", isActive: scenes.isRunning, color: .purple)
            }
            .padding(5)
            .background(.primary.opacity(0.045), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("MacFlow module status")

            Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .padding(.horizontal, MacFlowMetrics.detailPadding)
        .frame(height: MacFlowMetrics.topBarHeight)
    }

    private func topStatus(systemImage: String, isActive: Bool, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isActive ? color : .secondary.opacity(0.55))
            .frame(width: 27, height: 27)
            .background(isActive ? color.opacity(0.12) : .clear, in: Circle())
    }
}

private struct MacFlowSidebar: View {
    @Binding var selection: MacFlowSection
    let showsDebug: Bool
    let namespace: Namespace.ID

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var scenes: WallpaperSceneController
    @EnvironmentObject private var mouseFree: MouseFreeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredSection: MacFlowSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            brand
            sidebarGroup("WORKSPACE", sections: [.home, .notch, .mouseFree, .wallpaperEngine])
            Spacer(minLength: 12)
            sidebarGroup("MACFLOW", sections: systemSections)
            systemHealth
        }
        .padding(.horizontal, MacFlowMetrics.sidebarHorizontalPadding)
        .padding(.vertical, 14)
        .background(MacFlowTheme.sidebarSurface)
    }

    private var brand: some View {
        HStack(spacing: 11) {
            MacFlowLogoTile(size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("MacFlow")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Everything in rhythm")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.bottom, 2)
    }

    private func sidebarGroup(_ title: String, sections: [MacFlowSection]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.65))
                .tracking(1.1)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            ForEach(sections) { sidebarButton($0) }
        }
    }

    private func sidebarButton(_ section: MacFlowSection) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section

        return Button {
            NotchHaptics.perform(.navigation)
            withAnimation(MacFlowMotion.selection(reduceMotion: reduceMotion)) {
                selection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? section.accent : .secondary)
                    .frame(width: 25, height: 25)
                    .background(
                        isSelected ? section.accent.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                Text(section.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Capsule()
                        .fill(section.accent)
                        .frame(width: 3, height: 15)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 39)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.primary.opacity(0.07))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(section.accent.opacity(0.13), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "sidebar-selection", in: namespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.primary.opacity(0.035))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(MacFlowMotion.hover(reduceMotion: reduceMotion)) {
                hoveredSection = hovering ? section : nil
            }
        }
    }

    private var systemSections: [MacFlowSection] {
        var sections: [MacFlowSection] = [.preferences, .about]
        #if DEBUG
        if showsDebug { sections.append(.debug) }
        #endif
        return sections
    }

    private var systemHealth: some View {
        let activeCount = [
            settings.showNotch,
            mouseFree.status == .active,
            scenes.isRunning,
        ].filter { $0 }.count

        return HStack(spacing: 9) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12))
                Circle().fill(Color.green).frame(width: 6, height: 6)
            }
            .frame(width: 27, height: 27)
            VStack(alignment: .leading, spacing: 1) {
                Text(activeCount == 3 ? "Everything is flowing" : "MacFlow is ready")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("\(activeCount) of 3 modules active")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MacFlowTheme.subtleStroke, lineWidth: 1)
        }
    }
}

private struct MacFlowHomeView: View {
    @Binding var selection: MacFlowSection

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var scenes: WallpaperSceneController
    @EnvironmentObject private var mouseFree: MouseFreeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacFlowMetrics.sectionSpacing) {
                hero
                moduleGrid
                overview
            }
            .padding(MacFlowMetrics.detailPadding)
        }
        .scrollIndicators(.hidden)
    }

    private var hero: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 7) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("MACFLOW ONLINE")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                }

                Text("Make your Mac\nfeel like yours.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("One native workspace for the notch, scrolling, and a living desktop — connected without the clutter of separate apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .frame(maxWidth: 480, alignment: .leading)

                HStack(spacing: 9) {
                    Button {
                        move(to: .notch)
                    } label: {
                        Label("Open Notch", systemImage: "macbook")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MacFlowTheme.brandIndigo)

                    Button {
                        move(to: .wallpaperEngine)
                    } label: {
                        Label("Browse Scenes", systemImage: "photo.stack")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer(minLength: 8)
            MacFlowSystemVisual(
                notchActive: settings.showNotch,
                mouseActive: mouseFree.status == .active,
                wallpaperActive: scenes.isRunning
            )
            .frame(width: 290, height: 210)
        }
        .padding(26)
        .background {
            RoundedRectangle(cornerRadius: MacFlowMetrics.largeRadius, style: .continuous)
                .fill(MacFlowTheme.elevatedSurface)
                .overlay(alignment: .topTrailing) {
                    RadialGradient(
                        colors: [MacFlowTheme.brandIndigo.opacity(0.16), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 320
                    )
                    .clipShape(RoundedRectangle(cornerRadius: MacFlowMetrics.largeRadius, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowMetrics.largeRadius, style: .continuous)
                .stroke(MacFlowTheme.selectedStroke, lineWidth: 1)
        }
    }

    private var moduleGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 12
        ) {
            MacFlowModuleCard(
                section: .notch,
                status: settings.showNotch ? "Active" : "Paused",
                detail: "Media, calls, widgets and drops",
                isActive: settings.showNotch,
                preview: .notch
            ) { move(to: .notch) }

            MacFlowModuleCard(
                section: .mouseFree,
                status: mouseFree.status.title,
                detail: mouseFree.selectedPreset?.title ?? "Custom response",
                isActive: mouseFree.status == .active,
                preview: .mouse
            ) { move(to: .mouseFree) }

            MacFlowModuleCard(
                section: .wallpaperEngine,
                status: scenes.isRunning ? "Live" : "Ready",
                detail: "\(scenes.library.scenes.count) scene\(scenes.library.scenes.count == 1 ? "" : "s") in your library",
                isActive: scenes.isRunning,
                preview: .wallpaper
            ) { move(to: .wallpaperEngine) }
        }
    }

    private var overview: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Live overview")
                    .font(.headline)
                overviewRow(
                    icon: "waveform",
                    color: .cyan,
                    title: "Notch runtime",
                    value: settings.showNotch ? "Listening for activities" : "Paused"
                )
                Divider()
                overviewRow(
                    icon: "computermouse.fill",
                    color: .orange,
                    title: "Scroll profile",
                    value: mouseFree.selectedPreset?.title ?? "Custom"
                )
                Divider()
                overviewRow(
                    icon: "photo.fill",
                    color: .purple,
                    title: "Current scene",
                    value: scenes.activeScene?.title ?? "No active scene"
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .macFlowSurface()

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    MacFlowLogoTile(size: 36, showsShadow: false)
                    Spacer()
                    Text("LOCAL")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .tracking(0.9)
                }
                Text("One private runtime")
                    .font(.headline)
                Text("Your scenes, scrolling preferences, clipboard, calls and media state remain coordinated on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                Spacer(minLength: 8)
                Label("No duplicated background services", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
            .padding(20)
            .frame(width: 290, alignment: .topLeading)
            .macFlowSurface(accent: MacFlowTheme.brandIndigo)
        }
    }

    private func overviewRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 29, height: 29)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(value).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private func move(to destination: MacFlowSection) {
        NotchHaptics.perform(.navigation)
        withAnimation(MacFlowMotion.selection(reduceMotion: reduceMotion)) {
            selection = destination
        }
    }
}

private struct MacFlowSystemVisual: View {
    let notchActive: Bool
    let mouseActive: Bool
    let wallpaperActive: Bool

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let points = [
                    CGPoint(x: size.width * 0.18, y: size.height * 0.27),
                    CGPoint(x: size.width * 0.82, y: size.height * 0.27),
                    CGPoint(x: size.width * 0.50, y: size.height * 0.84),
                ]
                for point in points {
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: point)
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [MacFlowTheme.brandIndigo.opacity(0.65), .white.opacity(0.08)]),
                            startPoint: center,
                            endPoint: point
                        ),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 5])
                    )
                }
            }

            MacFlowLogoTile(size: 72)
            moduleNode(icon: "macbook", title: "Notch", color: .cyan, active: notchActive)
                .position(x: 52, y: 56)
            moduleNode(icon: "computermouse.fill", title: "Mouse", color: .orange, active: mouseActive)
                .position(x: 238, y: 56)
            moduleNode(icon: "photo.stack.fill", title: "Scenes", color: .purple, active: wallpaperActive)
                .position(x: 145, y: 175)
        }
    }

    private func moduleNode(
        icon: String,
        title: String,
        color: Color,
        active: Bool
    ) -> some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().stroke(color.opacity(0.20), lineWidth: 1) }
                Circle()
                    .fill(active ? .green : .secondary)
                    .frame(width: 7, height: 7)
                    .overlay { Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2) }
            }
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacFlowModuleCard: View {
    enum Preview { case notch, mouse, wallpaper }

    let section: MacFlowSection
    let status: String
    let detail: String
    let isActive: Bool
    let preview: Preview
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(section.accent)
                        .frame(width: 34, height: 34)
                        .background(section.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isActive ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 6, height: 6)
                        Text(status)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(isActive ? .green : .secondary)
                    }
                }

                modulePreview
                    .frame(height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(section.title)
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(section.accent)
                            .offset(x: isHovered ? 2 : 0, y: isHovered ? -2 : 0)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
            .macFlowSurface(accent: isHovered ? section.accent : nil)
            .scaleEffect(isHovered && !reduceMotion ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(MacFlowMotion.hover(reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var modulePreview: some View {
        switch preview {
        case .notch:
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.88))
                    .frame(height: 48)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black)
                    .frame(width: 72, height: 17)
                HStack {
                    Circle().fill(.cyan).frame(width: 7, height: 7)
                    Spacer()
                    Image(systemName: "waveform").foregroundStyle(.cyan)
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.top, 25)
            }
        case .mouse:
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 2, y: size.height * 0.78))
                path.addCurve(
                    to: CGPoint(x: size.width * 0.30, y: size.height * 0.18),
                    control1: CGPoint(x: size.width * 0.10, y: size.height * 0.78),
                    control2: CGPoint(x: size.width * 0.18, y: size.height * 0.16)
                )
                path.addCurve(
                    to: CGPoint(x: size.width - 2, y: size.height * 0.76),
                    control1: CGPoint(x: size.width * 0.48, y: size.height * 0.22),
                    control2: CGPoint(x: size.width * 0.62, y: size.height * 0.76)
                )
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [.orange, .orange.opacity(0.12)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    ),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                )
            }
            .padding(.horizontal, 4)
        case .wallpaper:
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MacFlowTheme.brandViolet.opacity(0.09))
                    .frame(width: 112, height: 50)
                    .rotationEffect(.degrees(-5))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MacFlowTheme.brandIndigo.opacity(0.75), MacFlowTheme.brandViolet.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 112, height: 50)
                    .rotationEffect(.degrees(3))
                    .overlay {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.white.opacity(0.9))
                    }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct MacFlowNotchModuleView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case overview, widgets, calendar, wallet, behavior, appearance
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @EnvironmentObject private var settings: NotchSettings
    @State private var tab: Tab = .overview

    var body: some View {
        VStack(spacing: 0) {
            moduleHeader
            Divider().opacity(0.55)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var moduleHeader: some View {
        HStack(spacing: 18) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.black)
                    .frame(width: 32, height: 9)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .padding(.top, 23)
            }
            .frame(width: 58, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notch workspace")
                    .font(.title3.weight(.semibold))
                Text("Shape what appears around your MacBook notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Notch section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 470)

            Toggle("Enable Notch", isOn: $settings.showNotch)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, MacFlowMetrics.detailPadding)
        .frame(height: 88)
    }

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .overview: GeneralSettingsView()
        case .widgets: WidgetSettingsView()
        case .calendar: CalendarSettingsView()
        case .wallet: WalletSettingsView()
        case .behavior: BehaviorSettingsView()
        case .appearance: AppearanceSettingsView()
        }
    }
}

private struct MacFlowPreferencesView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case general, appearance
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                MacFlowLogoTile(size: 46, showsShadow: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Shared preferences")
                        .font(.title3.weight(.semibold))
                    Text("Behavior and appearance used throughout MacFlow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Preferences", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, MacFlowMetrics.detailPadding)
            .frame(height: 88)
            Divider().opacity(0.55)

            if tab == .general {
                GeneralSettingsView()
            } else {
                AppearanceSettingsView()
            }
        }
    }
}
