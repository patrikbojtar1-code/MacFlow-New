//
//  WallpaperSceneAutomation.swift
//  NotchLand
//
//  Persistent collections and deterministic automation rules for Scenes.
//

import Foundation

nonisolated struct WallpaperSceneCollection: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case favorites
        case custom
    }

    let id: UUID
    var title: String
    var sceneIDs: [UUID]
    let kind: Kind
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        sceneIDs: [UUID] = [],
        kind: Kind = .custom,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.sceneIDs = sceneIDs
        self.kind = kind
        self.createdAt = createdAt
    }
}

nonisolated enum WallpaperDayPeriod: String, CaseIterable, Codable, Identifiable, Sendable {
    case morning
    case daytime
    case evening
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Morning"
        case .daytime: "Day"
        case .evening: "Evening"
        case .night: "Night"
        }
    }

    var systemImage: String {
        switch self {
        case .morning: "sunrise.fill"
        case .daytime: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    nonisolated static func current(
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> WallpaperDayPeriod {
        switch calendar.component(.hour, from: date) {
        case 5..<11: .morning
        case 11..<17: .daytime
        case 17..<22: .evening
        default: .night
        }
    }
}

nonisolated struct WallpaperAutomationConfiguration: Codable, Equatable, Sendable {
    enum RotationSource: String, Codable, CaseIterable, Identifiable, Sendable {
        case favorites
        case playlist

        var id: String { rawValue }

        var title: String {
            switch self {
            case .favorites: "Favorites"
            case .playlist: "Playlist"
            }
        }

        var systemImage: String {
            switch self {
            case .favorites: "star.fill"
            case .playlist: "music.note.list"
            }
        }
    }

    static let defaultRotationIntervalMinutes = 30
    static let supportedRotationIntervals = [5, 15, 30, 60]

    var isEnabled = false
    var rotatesFavorites = true
    var rotationIntervalMinutes = defaultRotationIntervalMinutes
    var rotationSource = RotationSource.favorites
    var rotationPlaylistID: UUID?
    var pausesRotationOnLowPower = true
    var focusSceneID: UUID?
    var lowPowerSceneID: UUID?
    var morningSceneID: UUID?
    var daytimeSceneID: UUID?
    var eveningSceneID: UUID?
    var nightSceneID: UUID?

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case rotatesFavorites
        case rotationIntervalMinutes
        case rotationSource
        case rotationPlaylistID
        case pausesRotationOnLowPower
        case focusSceneID
        case lowPowerSceneID
        case morningSceneID
        case daytimeSceneID
        case eveningSceneID
        case nightSceneID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        rotatesFavorites = try container.decodeIfPresent(Bool.self, forKey: .rotatesFavorites) ?? true
        rotationIntervalMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .rotationIntervalMinutes
        ) ?? Self.defaultRotationIntervalMinutes
        rotationSource = try container.decodeIfPresent(
            RotationSource.self,
            forKey: .rotationSource
        ) ?? .favorites
        rotationPlaylistID = try container.decodeIfPresent(UUID.self, forKey: .rotationPlaylistID)
        pausesRotationOnLowPower = try container.decodeIfPresent(
            Bool.self,
            forKey: .pausesRotationOnLowPower
        ) ?? true
        focusSceneID = try container.decodeIfPresent(UUID.self, forKey: .focusSceneID)
        lowPowerSceneID = try container.decodeIfPresent(UUID.self, forKey: .lowPowerSceneID)
        morningSceneID = try container.decodeIfPresent(UUID.self, forKey: .morningSceneID)
        daytimeSceneID = try container.decodeIfPresent(UUID.self, forKey: .daytimeSceneID)
        eveningSceneID = try container.decodeIfPresent(UUID.self, forKey: .eveningSceneID)
        nightSceneID = try container.decodeIfPresent(UUID.self, forKey: .nightSceneID)
    }

    func sceneID(for period: WallpaperDayPeriod) -> UUID? {
        switch period {
        case .morning: morningSceneID
        case .daytime: daytimeSceneID
        case .evening: eveningSceneID
        case .night: nightSceneID
        }
    }

    mutating func setSceneID(_ sceneID: UUID?, for period: WallpaperDayPeriod) {
        switch period {
        case .morning: morningSceneID = sceneID
        case .daytime: daytimeSceneID = sceneID
        case .evening: eveningSceneID = sceneID
        case .night: nightSceneID = sceneID
        }
    }
}

nonisolated enum WallpaperAutomationReason: Equatable, Sendable {
    case focus
    case lowPower
    case dayPeriod(WallpaperDayPeriod)
    case favoriteRotation
    case playlistRotation(String)

    var title: String {
        switch self {
        case .focus: "Focus scene"
        case .lowPower: "Low Power scene"
        case .dayPeriod(let period): "\(period.title) scene"
        case .favoriteRotation: "Favorite rotation"
        case .playlistRotation(let title): "\(title) rotation"
        }
    }

    var isRotation: Bool {
        switch self {
        case .favoriteRotation, .playlistRotation: true
        case .focus, .lowPower, .dayPeriod: false
        }
    }
}

nonisolated struct WallpaperAutomationRuleMatch: Equatable, Sendable {
    let sceneID: UUID
    let reason: WallpaperAutomationReason
}

nonisolated enum WallpaperAutomationRuleResolver {
    static func firstMatch(
        configuration: WallpaperAutomationConfiguration,
        availableSceneIDs: Set<UUID>,
        isFocusActive: Bool,
        isLowPowerModeEnabled: Bool,
        dayPeriod: WallpaperDayPeriod
    ) -> WallpaperAutomationRuleMatch? {
        if isFocusActive,
           let sceneID = configuration.focusSceneID,
           availableSceneIDs.contains(sceneID) {
            return WallpaperAutomationRuleMatch(sceneID: sceneID, reason: .focus)
        }
        if isLowPowerModeEnabled,
           let sceneID = configuration.lowPowerSceneID,
           availableSceneIDs.contains(sceneID) {
            return WallpaperAutomationRuleMatch(sceneID: sceneID, reason: .lowPower)
        }
        if let sceneID = configuration.sceneID(for: dayPeriod),
           availableSceneIDs.contains(sceneID) {
            return WallpaperAutomationRuleMatch(
                sceneID: sceneID,
                reason: .dayPeriod(dayPeriod)
            )
        }
        return nil
    }
}
