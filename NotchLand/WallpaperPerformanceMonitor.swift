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

        shouldSuspendVideo = thermalState == .critical
        guard selectedProfile == .automatic else {
            effectiveProfile = selectedProfile
            return
        }

        if isLowPowerModeEnabled || thermalState == .serious {
            effectiveProfile = .eco
        } else if thermalState == .fair {
            effectiveProfile = .balanced
        } else {
            effectiveProfile = .cinematic
        }
    }
}
