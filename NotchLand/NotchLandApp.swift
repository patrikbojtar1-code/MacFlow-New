//
//  NotchLandApp.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import SwiftUI

@main
struct NotchLandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            if AppRuntime.isXcodePreview {
                PreviewHostView()
            } else {
                SettingsView()
                    .environmentObject(appDelegate.settings)
                    .frame(width: 900, height: 620)
                    .environmentObject(appDelegate.appState)
                    .environmentObject(appDelegate.hud)
                    .environmentObject(appDelegate.batteryAlerts)
                    .environmentObject(appDelegate.focusMode)
                    .environmentObject(appDelegate.screenLock)
                    .environmentObject(appDelegate.biometrics)
                    .environmentObject(appDelegate.faceUnlock)
                    .environmentObject(appDelegate.calendar)
                    .environmentObject(appDelegate.eventCountdown)
                    .environmentObject(appDelegate.airDrop)
                    .environmentObject(appDelegate.fileShelf)
                    .environmentObject(appDelegate.quickNotes)
                    .environmentObject(appDelegate.todo)
                    .environmentObject(appDelegate.clipboard)
                    .environmentObject(appDelegate.quickActions)
                    .environmentObject(appDelegate.mirror)
                    .environmentObject(appDelegate.widgetPreferences)
                    .environmentObject(appDelegate.wallet)
                    .environmentObject(appDelegate.calls)
                    .environmentObject(appDelegate.systemCalls)
                    .environmentObject(appDelegate.liveActivities)
                    .environmentObject(appDelegate.eventCenter)
                    .environmentObject(appDelegate.shortcutsBridge)
                    .environmentObject(appDelegate.dropIntelligence)
                    .environmentObject(appDelegate.notchTimer)
                    .environmentObject(appDelegate.updater)
            }
        }
    }
}

private struct PreviewHostView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
