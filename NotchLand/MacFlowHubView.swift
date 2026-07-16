//
//  MacFlowHubView.swift
//  MacFlow
//
//  Persistent navigation shell for all MacFlow modules.
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
