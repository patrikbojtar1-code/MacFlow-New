//
//  MouseFreeController.swift
//  MacFlow
//
//  Shared settings, permissions, and lifecycle for the integrated MouseFree module.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

nonisolated enum MouseScrollPreset: String, CaseIterable, Identifiable, Sendable {
    case precise
    case balanced
    case macBook
    case glide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .precise: "Precise"
        case .balanced: "Balanced"
        case .macBook: "MacBook"
        case .glide: "Glide"
        }
    }

    var detail: String {
        switch self {
        case .precise: "Short, controlled movement"
        case .balanced: "Natural everyday scrolling"
        case .macBook: "Trackpad-like wheel feel"
        case .glide: "Long, soft momentum"
        }
    }

    var configuration: MouseScrollConfiguration {
        switch self {
        case .precise: .init(speed: 0.90, smoothness: 0.20, acceleration: 0.15)
        case .balanced: .init(speed: 1.15, smoothness: 0.45, acceleration: 0.30)
        case .macBook: .init(speed: 1.20, smoothness: 0.60, acceleration: 0.38)
        case .glide: .init(speed: 1.35, smoothness: 0.85, acceleration: 0.50)
        }
    }
}

@MainActor
final class MouseFreeController: ObservableObject {
    enum Status: Equatable {
        case disabled
        case needsAccessibility
        case active
        case unavailable

        var title: String {
            switch self {
            case .disabled: "Off"
            case .needsAccessibility: "Permission required"
            case .active: "Active"
            case .unavailable: "Unavailable"
            }
        }

        var systemImage: String {
            switch self {
            case .disabled: "pause.circle.fill"
            case .needsAccessibility: "lock.trianglebadge.exclamationmark.fill"
            case .active: "checkmark.circle.fill"
            case .unavailable: "exclamationmark.triangle.fill"
            }
        }
    }

    private enum Keys {
        static let enabled = "macflow.mouseFree.enabled"
        static let reverseScroll = "macflow.mouseFree.reverseScroll"
        static let speed = "macflow.mouseFree.speed"
        static let smoothness = "macflow.mouseFree.smoothness"
        static let acceleration = "macflow.mouseFree.acceleration"
        static let optionBypass = "macflow.mouseFree.optionBypass"
        static let preset = "macflow.mouseFree.preset"
    }

    private enum Defaults {
        static let enabled = false
        static let reverseScroll = true
        static let optionBypass = true
        static let preset = MouseScrollPreset.macBook
    }

    @Published var isEnabled: Bool { didSet { changed(Keys.enabled, value: isEnabled) } }
    @Published var reverseScroll: Bool { didSet { changed(Keys.reverseScroll, value: reverseScroll) } }
    @Published var speed: Double { didSet { normalizeAndPersist() } }
    @Published var smoothness: Double { didSet { normalizeAndPersist() } }
    @Published var acceleration: Double { didSet { normalizeAndPersist() } }
    @Published var optionBypassEnabled: Bool {
        didSet { changed(Keys.optionBypass, value: optionBypassEnabled) }
    }
    @Published private(set) var selectedPreset: MouseScrollPreset?
    @Published private(set) var status: Status = .disabled
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var hasRequestedAccessibilityThisRun = false

    /// Accessibility approval is tied to the installed app's code signature.
    /// A DerivedData or /tmp build receives a new ad-hoc identity on every build,
    /// so approving it would only work until the next compile.
    var isStableApplicationLocation: Bool {
        let applicationURL = Bundle.main.bundleURL.standardizedFileURL
        let path = applicationURL.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true).path + "/")
    }

    var applicationLocation: String {
        Bundle.main.bundleURL.standardizedFileURL.path
    }

    private let defaults: UserDefaults
    private let interceptor: MouseFreeScrollInterceptor
    private let trustProvider: () -> Bool
    private var isStarted = false
    private var isLoading = true
    private var isApplyingPreset = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        defaults: UserDefaults = .standard,
        interceptor: MouseFreeScrollInterceptor? = nil,
        trustProvider: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.defaults = defaults
        self.interceptor = interceptor ?? MouseFreeScrollInterceptor()
        self.trustProvider = trustProvider
        defaults.register(defaults: [
            Keys.enabled: Defaults.enabled,
            Keys.reverseScroll: Defaults.reverseScroll,
            Keys.optionBypass: Defaults.optionBypass,
            Keys.preset: Defaults.preset.rawValue,
            Keys.speed: Defaults.preset.configuration.speed,
            Keys.smoothness: Defaults.preset.configuration.smoothness,
            Keys.acceleration: Defaults.preset.configuration.acceleration,
        ])
        isEnabled = defaults.bool(forKey: Keys.enabled)
        reverseScroll = defaults.bool(forKey: Keys.reverseScroll)
        speed = defaults.double(forKey: Keys.speed)
        smoothness = defaults.double(forKey: Keys.smoothness)
        acceleration = defaults.double(forKey: Keys.acceleration)
        optionBypassEnabled = defaults.bool(forKey: Keys.optionBypass)
        selectedPreset = defaults.string(forKey: Keys.preset).flatMap(MouseScrollPreset.init)
        normalizeValues()
        isLoading = false
        refreshPermissionStatus()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshPermissionStatus() }
            .store(in: &cancellables)
        refreshPermissionStatus()
        synchronizeEngine()
    }

    func stop() {
        interceptor.stop()
        cancellables.removeAll()
        isStarted = false
        status = isEnabled ? .unavailable : .disabled
    }

    func apply(_ preset: MouseScrollPreset) {
        isApplyingPreset = true
        selectedPreset = preset
        let configuration = preset.configuration
        speed = configuration.speed
        smoothness = configuration.smoothness
        acceleration = configuration.acceleration
        defaults.set(preset.rawValue, forKey: Keys.preset)
        isApplyingPreset = false
        persistTuning()
        synchronizeEngine()
    }

    func refreshPermissionStatus() {
        isAccessibilityTrusted = trustProvider()
        synchronizeEngine()
    }

    func requestAccessibilityPermission() {
        guard !refreshAccessibilityTrust() else { return }
        guard !hasRequestedAccessibilityThisRun else { return }
        hasRequestedAccessibilityThisRun = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissionStatus()
    }

    @discardableResult
    private func refreshAccessibilityTrust() -> Bool {
        let trusted = trustProvider()
        isAccessibilityTrusted = trusted
        return trusted
    }

    private func changed(_ key: String, value: Any) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
        synchronizeEngine()
    }

    private func normalizeAndPersist() {
        guard !isLoading else { return }
        let normalizedSpeed = min(max(speed, 0.5), 3)
        let normalizedSmoothness = min(max(smoothness, 0), 1)
        let normalizedAcceleration = min(max(acceleration, 0), 1)
        if speed != normalizedSpeed { speed = normalizedSpeed; return }
        if smoothness != normalizedSmoothness { smoothness = normalizedSmoothness; return }
        if acceleration != normalizedAcceleration { acceleration = normalizedAcceleration; return }
        if !isApplyingPreset {
            selectedPreset = nil
            defaults.removeObject(forKey: Keys.preset)
            persistTuning()
            synchronizeEngine()
        }
    }

    private func normalizeValues() {
        speed = min(max(speed, 0.5), 3)
        smoothness = min(max(smoothness, 0), 1)
        acceleration = min(max(acceleration, 0), 1)
    }

    private func persistTuning() {
        defaults.set(speed, forKey: Keys.speed)
        defaults.set(smoothness, forKey: Keys.smoothness)
        defaults.set(acceleration, forKey: Keys.acceleration)
    }

    private func synchronizeEngine() {
        interceptor.reverseScroll = reverseScroll
        interceptor.scrollSpeed = speed
        interceptor.smoothFeel = smoothness
        interceptor.acceleration = acceleration
        interceptor.optionBypassEnabled = optionBypassEnabled

        guard isStarted, isEnabled else {
            interceptor.stop()
            status = .disabled
            return
        }
        guard isAccessibilityTrusted else {
            interceptor.stop()
            status = .needsAccessibility
            return
        }
        status = interceptor.start() ? .active : .unavailable
    }
}
