//
//  WallpaperPerformanceMonitor.swift
//  NotchLand
//
//  Maps user intent and system pressure to one effective rendering profile.
//

import Combine
import Foundation

@MainActor
final class WallpaperPerformanceMonitor: ObservableObject {
    private enum Keys {
        static let profile = "scenes.performanceProfile"
    }

    @Published var selectedProfile: WallpaperPerformanceProfile {
        didSet {
            defaults.set(selectedProfile.rawValue, forKey: Keys.profile)
            refresh()
        }
    }
    @Published private(set) var effectiveProfile: WallpaperPerformanceProfile = .balanced
    @Published private(set) var isLowPowerModeEnabled = false
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var shouldSuspendVideo = false

    private let processInfo: ProcessInfo
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(processInfo: ProcessInfo = .processInfo, defaults: UserDefaults = .standard) {
        self.processInfo = processInfo
        self.defaults = defaults
        selectedProfile = WallpaperPerformanceProfile(
            rawValue: defaults.string(forKey: Keys.profile) ?? ""
        ) ?? .automatic
        refresh()
    }

    func start() {
        guard cancellables.isEmpty else { return }
        let center = NotificationCenter.default
        center.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .merge(with: center.publisher(for: ProcessInfo.thermalStateDidChangeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    func stop() {
        cancellables.removeAll()
    }

    func refresh() {
        isLowPowerModeEnabled = processInfo.isLowPowerModeEnabled
        thermalState = processInfo.thermalState

        shouldSuspendVideo = Self.shouldSuspendVideo(for: thermalState)
        effectiveProfile = Self.resolvedProfile(
            selected: selectedProfile,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            thermalState: thermalState
        )
    }

    nonisolated static func shouldSuspendVideo(for thermalState: ProcessInfo.ThermalState) -> Bool {
        // A wallpaper is decorative work and should yield before macOS reaches
        // the critical thermal state.
        thermalState == .serious || thermalState == .critical
    }

    nonisolated static func resolvedProfile(
        selected: WallpaperPerformanceProfile,
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> WallpaperPerformanceProfile {
        guard selected == .automatic else { return selected }
        if isLowPowerModeEnabled || thermalState == .serious || thermalState == .critical {
            return .eco
        }
        // Automatic intentionally tops out at the efficient 1080p/30 FPS
        // budget. Users can still opt into Cinematic explicitly.
        return .balanced
    }
}
