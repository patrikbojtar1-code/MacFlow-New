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
    @AppStorage("macflow.selectedSection") private var selection: MacFlowSection = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #if NOTCHLAND_ENABLE_DEBUG_UI
    @AppStorage("settings.debugMenuUnlocked") private var debugMenuUnlocked = false
    @State private var aboutIconTapCount = 0
    #endif

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacFlowSidebarView(
                selection: $selection,
                showsDebug: showsDebug,
                onHideSidebar: hideSidebar
            )
                .navigationSplitViewColumnWidth(
                    min: 168,
                    ideal: MacFlowMetrics.sidebarWidth,
                    max: 240
                )
        } detail: {
            detail
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacFlowColor.canvas)
                .transition(.opacity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(
            minWidth: MacFlowMetrics.minimumWindowWidth,
            idealWidth: MacFlowMetrics.idealWindowWidth,
            minHeight: MacFlowMetrics.minimumWindowHeight,
            idealHeight: MacFlowMetrics.idealWindowHeight
        )
        .preferredColorScheme(settings.theme.colorScheme)
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

    private func hideSidebar() {
        MotionDebug.record(
            name: "sidebar.visibility",
            surface: "App Shell",
            duration: AppMotion.Duration.standard,
            state: "visible → hidden",
            reason: "User pressed the stable sidebar-leading hide control."
        )
        withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
            columnVisibility = .detailOnly
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
