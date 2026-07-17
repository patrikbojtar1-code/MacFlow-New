//
//  NotchSettings.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Single source of truth for user-configurable settings.
//  Each property reads its initial value from UserDefaults and writes back via didSet,
//  so persistence is centralized here and views/window-management can simply observe.
//

import Combine
import Foundation
import SwiftUI

nonisolated final class NotchSettings: ObservableObject {
    enum Theme: String, CaseIterable, Identifiable, Hashable {
        case system, dark, light

        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "System"
            case .dark: "Dark"
            case .light: "Light"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .dark: .dark
            case .light: .light
            }
        }
    }

    enum Defaults {
        static let showNotch = true
        static let launchAtLogin = false
        static let showMenuBarItem = true

        // Measured safe-area exclusion on the 13-inch M4 MacBook Air.
        static let collapsedWidth: Double = 179
        static let collapsedHeight: Double = 32
        static let expandedWidth: Double = 520
        static let expandedHeight: Double = 140
        static let notchContentSize: NotchSize = .small
        static let virtualNotchEnabled = true
        static let displayPolicy: NotchDisplayPolicy = .internalDisplay
        static let selectedDisplayIDs: Set<UInt32> = []
        static let displayConfigurations: [UInt32: DisplayNotchConfiguration] = [:]

        static let hoverToExpand = true
        static let collapseDelay: Double = 0.25
        static let autoCollapse = true
        static let openOnClick = true
        static let showHUDOnNotch = false
        static let lockUnlockAnimationEnabled = true
        static let biometricPrivacyEnabled = false
        static let systemCallDetectionEnabled = true

        static let theme: Theme = .system
        static let cornerRadius: Double = 20
        static let shadowIntensity: Double = 0
        static let useBlurMaterial = false

        static let eventCountdownEnabled = true
        static let eventCountdownThresholdMinutes = 30

        static let airDropEnabled = true
        static let fileShelfEnabled = true
        static let liveActivitiesEnabled = true
        static let autoUpdateCheckEnabled = true
        static let focusMonitorEnabled = true

        static let hasCompletedOnboarding = false
    }

    enum Limits {
        static let collapsedWidth: ClosedRange<Double> = 120...400
        static let collapsedHeight: ClosedRange<Double> = 32...80
        static let expandedWidth: ClosedRange<Double> = 320...900
        static let expandedHeight: ClosedRange<Double> = 160...600
        static let collapseDelay: ClosedRange<Double> = 0.05...1.0
        static let cornerRadius: ClosedRange<Double> = 6...40
        static let shadowIntensity: ClosedRange<Double> = 0...1
    }

    private enum Keys {
        static let showNotch = "notch.showNotch"
        static let launchAtLogin = "notch.launchAtLogin"
        static let showMenuBarItem = "notch.showMenuBarItem"
        static let collapsedWidth = "notch.collapsedWidth"
        static let collapsedHeight = "notch.collapsedHeight"
        static let expandedWidth = "notch.expandedWidth"
        static let expandedHeight = "notch.expandedHeight"
        static let notchContentSize = "notch.contentSize"
        static let virtualNotchEnabled = "notch.virtualNotchEnabled"
        static let displayPolicy = "notch.displayPolicy"
        static let selectedDisplayIDs = "notch.selectedDisplayIDs"
        static let displayConfigurations = "notch.displayConfigurations.v1"
        static let hoverToExpand = "notch.hoverToExpand"
        static let collapseDelay = "notch.collapseDelay"
        static let autoCollapse = "notch.autoCollapse"
        static let openOnClick = "notch.openOnClick"
        static let showHUDOnNotch = "notch.showHUDOnNotch"
        static let lockUnlockAnimationEnabled = "notch.lockUnlockAnimationEnabled"
        static let biometricPrivacyEnabled = "notch.biometricPrivacyEnabled"
        static let systemCallDetectionEnabled = "notch.systemCallDetectionEnabled"
        static let legacyHideSystemHUD = "notch.hideSystemHUD"
        static let theme = "notch.theme"
        static let cornerRadius = "notch.cornerRadius"
        static let shadowIntensity = "notch.shadowIntensity"
        static let useBlurMaterial = "notch.useBlurMaterial"
        static let eventCountdownEnabled = "notch.eventCountdownEnabled"
        static let eventCountdownThresholdMinutes = "notch.eventCountdownThresholdMinutes"
        static let airDropEnabled = "notch.airDropEnabled"
        static let fileShelfEnabled = "notch.fileShelfEnabled"
        static let liveActivitiesEnabled = "notch.liveActivitiesEnabled"
        static let autoUpdateCheckEnabled = "notch.autoUpdateCheckEnabled"
        static let focusMonitorEnabled = "notch.focusMonitorEnabled"
        static let hasCompletedOnboarding = "notch.hasCompletedOnboarding"
    }

    static let eventCountdownThresholdOptions: [Int] = [5, 15, 30, 60, 120]

    // General
    @Published var showNotch: Bool = read(Keys.showNotch, Defaults.showNotch) {
        didSet { Self.write(showNotch, Keys.showNotch) }
    }
    @Published var launchAtLogin: Bool = read(Keys.launchAtLogin, Defaults.launchAtLogin) {
        didSet { Self.write(launchAtLogin, Keys.launchAtLogin) }
    }
    @Published var showMenuBarItem: Bool = read(Keys.showMenuBarItem, Defaults.showMenuBarItem) {
        didSet { Self.write(showMenuBarItem, Keys.showMenuBarItem) }
    }

    // Sizes
    @Published var collapsedWidth: Double = read(Keys.collapsedWidth, Defaults.collapsedWidth) {
        didSet { Self.write(collapsedWidth, Keys.collapsedWidth) }
    }
    @Published var collapsedHeight: Double = read(Keys.collapsedHeight, Defaults.collapsedHeight) {
        didSet { Self.write(collapsedHeight, Keys.collapsedHeight) }
    }
    @Published var expandedWidth: Double = read(Keys.expandedWidth, Defaults.expandedWidth) {
        didSet { Self.write(expandedWidth, Keys.expandedWidth) }
    }
    @Published var expandedHeight: Double = read(Keys.expandedHeight, Defaults.expandedHeight) {
        didSet { Self.write(expandedHeight, Keys.expandedHeight) }
    }
    @Published var notchContentSize: NotchSize = readNotchSize() {
        didSet { Self.write(notchContentSize.rawValue, Keys.notchContentSize) }
    }
    @Published var virtualNotchEnabled: Bool = read(Keys.virtualNotchEnabled, Defaults.virtualNotchEnabled) {
        didSet { Self.write(virtualNotchEnabled, Keys.virtualNotchEnabled) }
    }
    @Published var displayPolicy: NotchDisplayPolicy = readDisplayPolicy() {
        didSet { Self.write(displayPolicy.rawValue, Keys.displayPolicy) }
    }
    @Published var selectedDisplayIDs: Set<UInt32> = readSelectedDisplayIDs() {
        didSet { Self.write(Array(selectedDisplayIDs).sorted(), Keys.selectedDisplayIDs) }
    }
    @Published var displayConfigurations: [UInt32: DisplayNotchConfiguration] = readDisplayConfigurations() {
        didSet { Self.writeDisplayConfigurations(displayConfigurations) }
    }

    // Behavior
    @Published var hoverToExpand: Bool = read(Keys.hoverToExpand, Defaults.hoverToExpand) {
        didSet { Self.write(hoverToExpand, Keys.hoverToExpand) }
    }
    @Published var collapseDelay: Double = read(Keys.collapseDelay, Defaults.collapseDelay) {
        didSet { Self.write(collapseDelay, Keys.collapseDelay) }
    }
    @Published var autoCollapse: Bool = read(Keys.autoCollapse, Defaults.autoCollapse) {
        didSet { Self.write(autoCollapse, Keys.autoCollapse) }
    }
    @Published var openOnClick: Bool = read(Keys.openOnClick, Defaults.openOnClick) {
        didSet { Self.write(openOnClick, Keys.openOnClick) }
    }
    @Published var showHUDOnNotch: Bool = readShowHUDOnNotch() {
        didSet { Self.write(showHUDOnNotch, Keys.showHUDOnNotch) }
    }
    @Published var lockUnlockAnimationEnabled: Bool = read(Keys.lockUnlockAnimationEnabled, Defaults.lockUnlockAnimationEnabled) {
        didSet { Self.write(lockUnlockAnimationEnabled, Keys.lockUnlockAnimationEnabled) }
    }
    @Published var biometricPrivacyEnabled: Bool = read(Keys.biometricPrivacyEnabled, Defaults.biometricPrivacyEnabled) {
        didSet { Self.write(biometricPrivacyEnabled, Keys.biometricPrivacyEnabled) }
    }
    @Published var systemCallDetectionEnabled: Bool = read(Keys.systemCallDetectionEnabled, Defaults.systemCallDetectionEnabled) {
        didSet { Self.write(systemCallDetectionEnabled, Keys.systemCallDetectionEnabled) }
    }

    // Appearance
    @Published var theme: Theme = readTheme() {
        didSet { Self.write(theme.rawValue, Keys.theme) }
    }
    @Published var cornerRadius: Double = read(Keys.cornerRadius, Defaults.cornerRadius) {
        didSet { Self.write(cornerRadius, Keys.cornerRadius) }
    }
    @Published var shadowIntensity: Double = read(Keys.shadowIntensity, Defaults.shadowIntensity) {
        didSet { Self.write(shadowIntensity, Keys.shadowIntensity) }
    }
    @Published var useBlurMaterial: Bool = read(Keys.useBlurMaterial, Defaults.useBlurMaterial) {
        didSet { Self.write(useBlurMaterial, Keys.useBlurMaterial) }
    }

    // Calendar countdown
    @Published var eventCountdownEnabled: Bool = read(Keys.eventCountdownEnabled, Defaults.eventCountdownEnabled) {
        didSet { Self.write(eventCountdownEnabled, Keys.eventCountdownEnabled) }
    }
    @Published var eventCountdownThresholdMinutes: Int = read(Keys.eventCountdownThresholdMinutes, Defaults.eventCountdownThresholdMinutes) {
        didSet { Self.write(eventCountdownThresholdMinutes, Keys.eventCountdownThresholdMinutes) }
    }

    // AirDrop, activities, updates
    @Published var airDropEnabled: Bool = read(Keys.airDropEnabled, Defaults.airDropEnabled) {
        didSet { Self.write(airDropEnabled, Keys.airDropEnabled) }
    }
    @Published var fileShelfEnabled: Bool = read(Keys.fileShelfEnabled, Defaults.fileShelfEnabled) {
        didSet { Self.write(fileShelfEnabled, Keys.fileShelfEnabled) }
    }
    @Published var liveActivitiesEnabled: Bool = read(Keys.liveActivitiesEnabled, Defaults.liveActivitiesEnabled) {
        didSet { Self.write(liveActivitiesEnabled, Keys.liveActivitiesEnabled) }
    }
    @Published var autoUpdateCheckEnabled: Bool = read(Keys.autoUpdateCheckEnabled, Defaults.autoUpdateCheckEnabled) {
        didSet { Self.write(autoUpdateCheckEnabled, Keys.autoUpdateCheckEnabled) }
    }
    @Published var focusMonitorEnabled: Bool = read(Keys.focusMonitorEnabled, Defaults.focusMonitorEnabled) {
        didSet { Self.write(focusMonitorEnabled, Keys.focusMonitorEnabled) }
    }

    // Onboarding — flipped to true the first time the user taps GET STARTED.
    @Published var hasCompletedOnboarding: Bool = read(Keys.hasCompletedOnboarding, Defaults.hasCompletedOnboarding) {
        didSet { Self.write(hasCompletedOnboarding, Keys.hasCompletedOnboarding) }
    }

    func resetToDefaults() {
        showNotch = Defaults.showNotch
        launchAtLogin = Defaults.launchAtLogin
        showMenuBarItem = Defaults.showMenuBarItem
        collapsedWidth = Defaults.collapsedWidth
        collapsedHeight = Defaults.collapsedHeight
        expandedWidth = Defaults.expandedWidth
        expandedHeight = Defaults.expandedHeight
        notchContentSize = Defaults.notchContentSize
        virtualNotchEnabled = Defaults.virtualNotchEnabled
        displayPolicy = Defaults.displayPolicy
        selectedDisplayIDs = Defaults.selectedDisplayIDs
        displayConfigurations = Defaults.displayConfigurations
        hoverToExpand = Defaults.hoverToExpand
        collapseDelay = Defaults.collapseDelay
        autoCollapse = Defaults.autoCollapse
        openOnClick = Defaults.openOnClick
        showHUDOnNotch = Defaults.showHUDOnNotch
        lockUnlockAnimationEnabled = Defaults.lockUnlockAnimationEnabled
        biometricPrivacyEnabled = Defaults.biometricPrivacyEnabled
        systemCallDetectionEnabled = Defaults.systemCallDetectionEnabled
        theme = Defaults.theme
        cornerRadius = Defaults.cornerRadius
        shadowIntensity = Defaults.shadowIntensity
        useBlurMaterial = Defaults.useBlurMaterial
        eventCountdownEnabled = Defaults.eventCountdownEnabled
        eventCountdownThresholdMinutes = Defaults.eventCountdownThresholdMinutes
        airDropEnabled = Defaults.airDropEnabled
        fileShelfEnabled = Defaults.fileShelfEnabled
        liveActivitiesEnabled = Defaults.liveActivitiesEnabled
        autoUpdateCheckEnabled = Defaults.autoUpdateCheckEnabled
        focusMonitorEnabled = Defaults.focusMonitorEnabled
    }

    func resetToFactoryDefaults() {
        resetToDefaults()
        hasCompletedOnboarding = Defaults.hasCompletedOnboarding
    }

    func resetSizesToDefaults() {
        collapsedWidth = Defaults.collapsedWidth
        collapsedHeight = Defaults.collapsedHeight
        expandedWidth = Defaults.expandedWidth
        expandedHeight = Defaults.expandedHeight
        notchContentSize = Defaults.notchContentSize
        displayConfigurations = Defaults.displayConfigurations
    }

    private static func read<T>(_ key: String, _ fallback: T) -> T {
        AppDefaults.store.object(forKey: key) as? T ?? fallback
    }

    private static func write<T>(_ value: T, _ key: String) {
        AppDefaults.store.set(value, forKey: key)
    }

    private static func readTheme() -> Theme {
        if let raw = AppDefaults.store.string(forKey: Keys.theme),
           let theme = Theme(rawValue: raw) {
            return theme
        }
        return Defaults.theme
    }

    private static func readNotchSize() -> NotchSize {
        guard let rawValue = AppDefaults.store.string(forKey: Keys.notchContentSize),
              let size = NotchSize(rawValue: rawValue) else {
            return Defaults.notchContentSize
        }
        return size
    }

    private static func readDisplayPolicy() -> NotchDisplayPolicy {
        guard let rawValue = AppDefaults.store.string(forKey: Keys.displayPolicy),
              let policy = NotchDisplayPolicy(rawValue: rawValue) else {
            return Defaults.displayPolicy
        }
        return policy
    }

    private static func readSelectedDisplayIDs() -> Set<UInt32> {
        let values = AppDefaults.store.array(forKey: Keys.selectedDisplayIDs) as? [NSNumber] ?? []
        return Set(values.map(\.uint32Value))
    }

    func contentSize(for displayID: UInt32?) -> NotchSize {
        guard let displayID else { return notchContentSize }
        return displayConfigurations[displayID]?.contentSize ?? notchContentSize
    }

    func horizontalOffset(for displayID: UInt32) -> CGFloat {
        CGFloat(displayConfigurations[displayID]?.horizontalOffset ?? 0)
    }

    func setContentSize(_ size: NotchSize, for displayID: UInt32) {
        var configuration = displayConfigurations[displayID]
            ?? DisplayNotchConfiguration(contentSize: notchContentSize)
        configuration.contentSize = size
        displayConfigurations[displayID] = configuration
    }

    func setHorizontalOffset(_ offset: Double, for displayID: UInt32) {
        var configuration = displayConfigurations[displayID]
            ?? DisplayNotchConfiguration(contentSize: notchContentSize)
        configuration.horizontalOffset = min(max(offset, -240), 240)
        displayConfigurations[displayID] = configuration
    }

    private static func readDisplayConfigurations() -> [UInt32: DisplayNotchConfiguration] {
        guard let data = AppDefaults.store.data(forKey: Keys.displayConfigurations),
              let stored = try? JSONDecoder().decode(
                [String: DisplayNotchConfiguration].self,
                from: data
              ) else { return Defaults.displayConfigurations }
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            UInt32(key).map { ($0, value) }
        })
    }

    private static func writeDisplayConfigurations(
        _ configurations: [UInt32: DisplayNotchConfiguration]
    ) {
        let stored = Dictionary(uniqueKeysWithValues: configurations.map { key, value in
            (String(key), value)
        })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        AppDefaults.store.set(data, forKey: Keys.displayConfigurations)
    }

    private static func readShowHUDOnNotch() -> Bool {
        if let value = AppDefaults.store.object(forKey: Keys.showHUDOnNotch) as? Bool {
            return value
        }
        return AppDefaults.store.object(forKey: Keys.legacyHideSystemHUD) as? Bool ?? Defaults.showHUDOnNotch
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
