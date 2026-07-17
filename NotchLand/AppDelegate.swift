//
//  AppDelegate.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Bootstraps the singletons (NotchSettings, AppState, WindowManager) and
//  exposes settings/appState to the SwiftUI Settings scene.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = NotchSettings()
    lazy var appState = AppState(settings: settings)
    lazy var hud = HUDController(settings: settings)
    lazy var nowPlaying = NowPlayingService()
    lazy var batteryAlerts = BatteryAlertController()
    lazy var focusMode = FocusModeController()
    lazy var screenLock = ScreenLockController(settings: settings)
    lazy var biometrics = BiometricAuthenticationController()
    lazy var calendar = CalendarService()
    lazy var eventCountdown = EventCountdownController(calendar: calendar, settings: settings)
    lazy var airDrop = AirDropController(settings: settings)
    lazy var fileShelf = FileShelfController(settings: settings)
    lazy var quickNotes = QuickNotesController()
    lazy var todo = TodoController()
    lazy var clipboard = ClipboardController()
    lazy var quickActions = QuickActionsController()
    lazy var mirror = MirrorController()
    lazy var widgetPreferences = WidgetPreferencesController()
    lazy var wallet = WalletContributionController()
    lazy var calls = CallActivityController()
    lazy var systemCalls = SystemCallActivitySource(calls: calls, settings: settings)
    lazy var liveActivities = LiveActivityController(settings: settings)
    lazy var systemMessages = SystemMessageActivitySource(activities: liveActivities, settings: settings)
    lazy var systemActivityMonitor = SystemAccessibilityActivityMonitor(
        calls: systemCalls,
        messages: systemMessages,
        settings: settings
    )
    lazy var eventCenter = NotchEventCenter()
    lazy var shortcutsBridge = ShortcutsBridgeController(events: eventCenter)
    lazy var dropIntelligence = DropIntelligenceController()
    lazy var eventBridge = NotchEventBridge(
        center: eventCenter,
        wallet: wallet,
        calls: calls,
        battery: batteryAlerts,
        focus: focusMode,
        activities: liveActivities,
        preferences: widgetPreferences
    )
    lazy var audioActivity = AudioDeviceActivitySource(activities: liveActivities)
    lazy var notchTimer = NotchTimerController(activities: liveActivities)
    lazy var downloadsActivity = DownloadsActivitySource(activities: liveActivities)
    lazy var sceneLibrary = WallpaperSceneLibrary()
    lazy var scenePerformance = WallpaperPerformanceMonitor()
    lazy var scenes = WallpaperSceneController(
        library: sceneLibrary,
        performance: scenePerformance,
        focusMode: focusMode
    )
    lazy var mouseFree = MouseFreeController()
    lazy var updater = UpdaterController(settings: settings)
    private var didStartServices = false
    private lazy var windowManager = WindowManager(
        settings: settings,
        appState: appState,
        hud: hud,
        nowPlaying: nowPlaying,
        batteryAlerts: batteryAlerts,
        focusMode: focusMode,
        screenLock: screenLock,
        biometrics: biometrics,
        calendar: calendar,
        eventCountdown: eventCountdown,
        airDrop: airDrop,
        fileShelf: fileShelf,
        quickNotes: quickNotes,
        todo: todo,
        clipboard: clipboard,
        quickActions: quickActions,
        mirror: mirror,
        widgetPreferences: widgetPreferences,
        wallet: wallet,
        calls: calls,
        systemCalls: systemCalls,
        liveActivities: liveActivities,
        eventCenter: eventCenter,
        shortcutsBridge: shortcutsBridge,
        dropIntelligence: dropIntelligence,
        notchTimer: notchTimer,
        scenes: scenes,
        mouseFree: mouseFree,
        updater: updater
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppRuntime.shouldStartApplicationServices else { return }
        NSApp.setActivationPolicy(.accessory)
        NotchIntentRuntime.shared.configure(
            appState: appState,
            timer: notchTimer,
            notes: quickNotes,
            biometrics: biometrics
        )
        windowManager.start()
        hud.start()
        batteryAlerts.start()
        focusMode.start()
        screenLock.start()
        systemCalls.start()
        systemMessages.start()
        systemActivityMonitor.start()
        calendar.start()
        eventCountdown.start()
        clipboard.startMonitoring()
        wallet.start()
        audioActivity.start()
        downloadsActivity.start()
        scenes.start()
        mouseFree.start()
        eventBridge.start()
        didStartServices = true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard didStartServices else { return }
        hud.stop()
        batteryAlerts.stop()
        focusMode.stop()
        screenLock.stop()
        systemActivityMonitor.stop()
        systemCalls.stop()
        systemMessages.stop()
        calendar.stop()
        eventCountdown.stop()
        clipboard.stopMonitoring()
        wallet.stop()
        mirror.stop()
        audioActivity.stop()
        downloadsActivity.stop()
        scenes.stop()
        mouseFree.stop()
        eventBridge.stop()
        notchTimer.suspend()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let sceneURL = urls.first(where: WallpaperSceneFileSupport.isSupportedImport) else {
            return
        }
        Task { @MainActor in
            _ = await scenes.importAndApply(from: sceneURL)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
