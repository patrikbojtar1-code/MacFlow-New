//
//  WallpaperSceneAutomation.swift
//  NotchLand
//
//  Persistent collections and deterministic automation rules for Scenes.
//

import Foundation

struct WallpaperSceneCollection: Codable, Identifiable, Hashable, Sendable {
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

enum WallpaperDayPeriod: String, CaseIterable, Codable, Identifiable, Sendable {
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

struct WallpaperAutomationConfiguration: Codable, Equatable, Sendable {
    static let defaultRotationIntervalMinutes = 30
    static let supportedRotationIntervals = [5, 15, 30, 60]

    var isEnabled = false
    var rotatesFavorites = true
    var rotationIntervalMinutes = defaultRotationIntervalMinutes
    var focusSceneID: UUID?
    var morningSceneID: UUID?
    var daytimeSceneID: UUID?
    var eveningSceneID: UUID?
    var nightSceneID: UUID?

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

enum WallpaperAutomationReason: Equatable, Sendable {
    case focus
    case dayPeriod(WallpaperDayPeriod)
    case favoriteRotation

    var title: String {
        switch self {
        case .focus: "Focus scene"
        case .dayPeriod(let period): "\(period.title) scene"
        case .favoriteRotation: "Favorite rotation"
        }
    }
}
