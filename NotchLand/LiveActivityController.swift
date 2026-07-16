//
//  LiveActivityController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  One compact chip beside the notch at a time, newest wins (same policy as
//  the HUD queue). Sources (audio connect, timer, downloads) post,
//  update by re-posting the same id, and end activities.
//

import Combine
import Foundation

enum AudioAccessoryModel: String, Equatable, Sendable {
    case macBookAirM4
    case airPodsMax
    case airPodsPro
    case airPods3
    case airPods2
    case beats
    case headphones
    case generic

    static func detect(from deviceName: String) -> Self {
        let value = deviceName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased()
        if value.contains("macbook air") || value.contains("built-in") || value.contains("speaker") {
            return .macBookAirM4
        }
        if value.contains("airpods max") { return .airPodsMax }
        if value.contains("airpods pro") { return .airPodsPro }
        if value.contains("airpods 3") || value.contains("airpods (3") || value.contains("airpods gen 3") { return .airPods3 }
        if value.contains("airpods") { return .airPods2 }
        if value.contains("beats") { return .beats }
        if value.contains("headphone") || value.contains("sluch") { return .headphones }
        return .generic
    }

    var symbolName: String {
        switch self {
        case .macBookAirM4: "macbook"
        case .airPodsMax: "airpodsmax"
        case .airPodsPro: "airpodspro"
        case .airPods3: "airpods.gen3"
        case .airPods2: "airpods"
        case .beats, .headphones: "headphones"
        case .generic: "hifispeaker.fill"
        }
    }
}

enum AudioAccessoryConnectionPhase: String, Equatable, Sendable {
    case connecting
    case connected
    case disconnecting
    case disconnected
    case lowBattery

    var displayName: String {
        switch self {
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting…"
        case .disconnected: "Disconnected"
        case .lowBattery: "Low Battery"
        }
    }
}

struct LiveActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case audioDevice(
            name: String,
            model: AudioAccessoryModel,
            batteryPercent: Int?,
            phase: AudioAccessoryConnectionPhase
        )
        case message(sender: String)
        case timer(remaining: TimeInterval)
        case download(fileName: String)
    }

    let id: UUID
    let kind: Kind
    var title: String
    var detail: String?
    var progress: Double?

    init(id: UUID = UUID(), kind: Kind, title: String, detail: String?, progress: Double?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.progress = progress
    }

    var branchKey: String { "activity" }
}

extension LiveActivity: NotchActivityPresenting {
    var activityType: NotchActivityType {
        switch kind {
        case .audioDevice: .bluetooth
        case .message, .download: .systemStatus
        case .timer: .timer
        }
    }

    var presentationID: String { id.uuidString }
    var primaryTitle: String { title }
    var secondaryTitle: String { detail ?? "" }
}

@MainActor
final class LiveActivityController: ObservableObject {
    @Published private(set) var current: LiveActivity?

    private let settings: NotchSettings

    init(settings: NotchSettings) {
        self.settings = settings
    }

    func post(_ activity: LiveActivity) {
        guard settings.liveActivitiesEnabled else { return }
        current = activity
    }

    func end(_ id: UUID) {
        if current?.id == id {
            current = nil
        }
    }

    func endAll() {
        current = nil
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
