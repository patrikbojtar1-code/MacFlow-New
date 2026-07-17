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
    #if DEBUG
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
    }

    private var showsDebug: Bool {
        #if DEBUG
        debugMenuUnlocked
        #else
        false
        #endif
    }

    private func hideSidebar() {
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
