//
//  MacFlowHubView.swift
//  MacFlow
//
//  Native, adaptive navigation shell shared by every MacFlow module.
//

import SwiftUI

struct MacFlowHubView: View {
    @EnvironmentObject private var settings: NotchSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("macflow.selectedSection", store: AppDefaults.store)
    private var selection: MacFlowSection = .home
    @AppStorage("macflow.sidebar.isCollapsed", store: AppDefaults.store)
    private var isSidebarCollapsed = false
    #if NOTCHLAND_ENABLE_DEBUG_UI
    @AppStorage("settings.debugMenuUnlocked", store: AppDefaults.store)
    private var debugMenuUnlocked = false
    @State private var aboutIconTapCount = 0
    #endif

    var body: some View {
        HStack(spacing: 0) {
            MacFlowSidebarView(
                selection: $selection,
                showsDebug: showsDebug,
                isCollapsed: isSidebarCollapsed,
                onToggleSidebar: toggleSidebar
            )
            .frame(width: isSidebarCollapsed ? 52 : MacFlowMetrics.sidebarWidth)
            .clipped()

            Divider()

            detail
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacFlowColor.canvas)
                .transition(.opacity)
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .animation(AppMotion.stateChange(reduceMotion: reduceMotion), value: isSidebarCollapsed)
        .motionDebugProbe("App Shell")
        .onChange(of: selection) { oldSection, newSection in
            MotionDebug.record(
                name: "app.section",
                surface: "App Shell",
                duration: AppMotion.Duration.quick,
                state: "\(oldSection.rawValue) → \(newSection.rawValue)",
                reason: "User selected a different primary workspace."
            )
        }
    }

    private var showsDebug: Bool {
        #if NOTCHLAND_ENABLE_DEBUG_UI
        debugMenuUnlocked
        #else
        false
        #endif
    }

    private func toggleSidebar() {
        let nextState = !isSidebarCollapsed
        MotionDebug.record(
            name: "sidebar.visibility",
            surface: "App Shell",
            duration: AppMotion.Duration.standard,
            state: nextState ? "expanded → collapsed" : "collapsed → expanded",
            reason: "User pressed the stable control owned by the sidebar rail."
        )
        withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
            isSidebarCollapsed = nextState
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home:
            MacFlowHomeView(selection: $selection)
        case .notch:
            MacFlowNotchWorkspaceView()
        case .mouseFree:
            MouseFreeHubView()
        case .wallpaperEngine:
            ScenesSettingsView()
        case .preferences:
            MacFlowPreferencesView()
        case .about:
            AboutSettingsView(onIconClick: handleAboutIconClick)
        #if NOTCHLAND_ENABLE_DEBUG_UI
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
        #if NOTCHLAND_ENABLE_DEBUG_UI
        guard !debugMenuUnlocked else { return }
        aboutIconTapCount += 1
        if aboutIconTapCount >= 7 {
            debugMenuUnlocked = true
            selection = .debug
        }
        #endif
    }
}
