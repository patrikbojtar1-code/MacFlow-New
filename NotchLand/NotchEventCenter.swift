//
//  NotchEventCenter.swift
//  NotchLand
//
//  Normalized event pipeline for every transient notch integration. Feature
//  controllers remain independent; this center owns priority, interruption,
//  deduplication, queue promotion, and a privacy-safe local history.
//

import Combine
import Foundation

nonisolated enum NotchEventSource: String, Codable, CaseIterable, Sendable {
    case wallet
    case call
    case battery
    case focus
    case liveActivity
    case system
    case calendar
    case files
    case integration

    var title: String {
        switch self {
        case .wallet: "Wallet"
        case .call: "Calls"
        case .battery: "Battery"
        case .focus: "Focus"
        case .liveActivity: "Live Activity"
        case .system: "System"
        case .calendar: "Calendar"
        case .files: "Files"
        case .integration: "Integration"
        }
    }
}

nonisolated enum NotchEventPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case background = 0
    case passive = 100
    case normal = 200
    case important = 300
    case critical = 400

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct NotchEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let correlationID: String
    let source: NotchEventSource
    var title: String
    var detail: String?
    var symbol: String
    var priority: NotchEventPriority
    var progress: Double?
    let createdAt: Date
    var updatedAt: Date
    var isRead: Bool

    init(
        id: UUID = UUID(),
        correlationID: String,
        source: NotchEventSource,
        title: String,
        detail: String? = nil,
        symbol: String,
        priority: NotchEventPriority,
        progress: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isRead: Bool = false
    ) {
        self.id = id
        self.correlationID = correlationID
        self.source = source
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.priority = priority
        self.progress = progress.map { min(max($0, 0), 1) }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isRead = isRead
    }
}

@MainActor
final class NotchEventCenter: ObservableObject {
    @Published private(set) var current: NotchEvent?
    @Published private(set) var pending: [NotchEvent] = []
    @Published private(set) var history: [NotchEvent] = []

    private enum Keys {
        static let history = "notch.events.history.v1"
    }

    private let defaults: UserDefaults
    private let historyLimit: Int

    init(defaults: UserDefaults = .standard, historyLimit: Int = 100) {
        self.defaults = defaults
        self.historyLimit = max(1, historyLimit)
        restoreHistory()
    }

    var unreadCount: Int {
        history.lazy.filter { !$0.isRead }.count
    }

    func submit(_ event: NotchEvent, presents: Bool = true) {
        let normalized = normalizedUpdate(event)
        upsertHistory(normalized)

        guard presents else {
            resolve(correlationID: normalized.correlationID)
            return
        }

        if current?.correlationID == normalized.correlationID {
            current = normalized
            return
        }

        pending.removeAll { $0.correlationID == normalized.correlationID }
        guard let active = current else {
            current = normalized
            return
        }

        if normalized.priority > active.priority {
            pending.append(active)
            current = normalized
        } else {
            pending.append(normalized)
        }
        sortPending()
    }

    func resolve(correlationID: String) {
        if current?.correlationID == correlationID {
            current = nil
            promoteNext()
        } else {
            pending.removeAll { $0.correlationID == correlationID }
        }
    }

    func dismissCurrent() {
        guard let current else { return }
        markRead(current)
        resolve(correlationID: current.correlationID)
        NotchHaptics.perform(.navigation)
    }

    func resolve(source: NotchEventSource) {
        if current?.source == source {
            current = nil
        }
        pending.removeAll { $0.source == source }
        promoteNext()
    }

    func markRead(_ event: NotchEvent) {
        guard let index = history.firstIndex(where: { $0.id == event.id }),
              !history[index].isRead else { return }
        history[index].isRead = true
        persistHistory()
    }

    func markAllRead() {
        guard history.contains(where: { !$0.isRead }) else { return }
        for index in history.indices {
            history[index].isRead = true
        }
        persistHistory()
    }

    func clearHistory() {
        history = []
        persistHistory()
    }

    private func normalizedUpdate(_ event: NotchEvent) -> NotchEvent {
        guard let previous = history.first(where: { $0.correlationID == event.correlationID }) else {
            return event
        }
        var update = event
        update = NotchEvent(
            id: previous.id,
            correlationID: event.correlationID,
            source: event.source,
            title: event.title,
            detail: event.detail,
            symbol: event.symbol,
            priority: event.priority,
            progress: event.progress,
            createdAt: previous.createdAt,
            updatedAt: event.updatedAt,
            isRead: false
        )
        return update
    }

    private func upsertHistory(_ event: NotchEvent) {
        history.removeAll { $0.correlationID == event.correlationID }
        history.insert(event, at: 0)
        history = Array(history.prefix(historyLimit))
        persistHistory()
    }

    private func promoteNext() {
        guard current == nil, !pending.isEmpty else { return }
        sortPending()
        current = pending.removeFirst()
    }

    private func sortPending() {
        pending.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.updatedAt < $1.updatedAt
        }
    }

    private func restoreHistory() {
        guard let data = defaults.data(forKey: Keys.history),
              let saved = try? JSONDecoder().decode([NotchEvent].self, from: data) else { return }
        history = Array(saved.sorted { $0.updatedAt > $1.updatedAt }.prefix(historyLimit))
    }

    private func persistHistory() {
        defaults.set(try? JSONEncoder().encode(history), forKey: Keys.history)
    }
}

enum NotchEventPresentationRoute: Equatable {
    case call
    case battery
    case focus
    case wallet
    case liveActivity
}

enum NotchEventPresentationPolicy {
    static func route(
        for event: NotchEvent?,
        isExpanded: Bool,
        isWalletVisible: Bool
    ) -> NotchEventPresentationRoute? {
        guard let event else { return nil }
        switch event.source {
        case .call:
            return .call
        case .battery:
            return .battery
        case .focus:
            return .focus
        case .wallet:
            return !isExpanded && isWalletVisible ? .wallet : nil
        case .liveActivity:
            return !isExpanded ? .liveActivity : nil
        case .system, .calendar, .files, .integration:
            return nil
        }
    }
}

@MainActor
final class NotchEventBridge {
    private let center: NotchEventCenter
    private let wallet: WalletContributionController
    private let calls: CallActivityController
    private let battery: BatteryAlertController
    private let focus: FocusModeController
    private let activities: LiveActivityController
    private let preferences: WidgetPreferencesController
    private var cancellables: Set<AnyCancellable> = []

    init(
        center: NotchEventCenter,
        wallet: WalletContributionController,
        calls: CallActivityController,
        battery: BatteryAlertController,
        focus: FocusModeController,
        activities: LiveActivityController,
        preferences: WidgetPreferencesController
    ) {
        self.center = center
        self.wallet = wallet
        self.calls = calls
        self.battery = battery
        self.focus = focus
        self.activities = activities
        self.preferences = preferences
    }

    func start() {
        guard cancellables.isEmpty else { return }

        Publishers.CombineLatest(
            wallet.$currentContribution.removeDuplicates(),
            preferences.$visibilityModes.removeDuplicates()
        )
            .sink { [weak self] contribution, modes in
                self?.ingest(contribution, presents: modes[.wallet] != .hidden)
            }
            .store(in: &cancellables)

        calls.$current
            .removeDuplicates()
            .sink { [weak self] call in self?.ingest(call) }
            .store(in: &cancellables)

        battery.$currentPresentation
            .removeDuplicates()
            .sink { [weak self] presentation in self?.ingest(presentation) }
            .store(in: &cancellables)

        focus.$currentPresentation
            .removeDuplicates()
            .sink { [weak self] presentation in self?.ingest(presentation) }
            .store(in: &cancellables)

        activities.$current
            .removeDuplicates()
            .sink { [weak self] activity in self?.ingest(activity) }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    private func ingest(_ contribution: WalletContribution?, presents: Bool) {
        guard let contribution else {
            center.resolve(source: .wallet)
            return
        }
        center.submit(NotchEvent(
            correlationID: "wallet:\(contribution.id)",
            source: .wallet,
            title: "Payment received",
            detail: "+\(contribution.amount) \(contribution.network.ticker)",
            symbol: contribution.network.symbol,
            priority: .important,
            createdAt: contribution.date
        ), presents: presents)
    }

    private func ingest(_ call: CallPresentation?) {
        guard let call else {
            center.resolve(source: .call)
            return
        }
        let state: (String, String, NotchEventPriority) = switch call.phase {
        case .incoming: ("Incoming call", "phone.fill", .critical)
        case .connecting: ("Connecting", "phone.connection.fill", .critical)
        case .active: ("Call in progress", "phone.fill", .critical)
        case .ended(let reason): (reason, "phone.down.fill", .important)
        case .missed: ("Missed call", "phone.badge.waveform.fill", .important)
        }
        center.submit(NotchEvent(
            correlationID: "call:\(call.id.uuidString)",
            source: .call,
            title: state.0,
            detail: "\(call.callerName) · \(call.serviceName)",
            symbol: state.1,
            priority: state.2
        ))
    }

    private func ingest(_ presentation: BatteryAlertController.Presentation?) {
        guard let presentation else {
            center.resolve(source: .battery)
            return
        }
        switch presentation {
        case .lowBattery(let alert):
            center.submit(NotchEvent(
                correlationID: "battery:low:\(alert.milestone)",
                source: .battery,
                title: alert.title,
                detail: "\(alert.percent)% · \(alert.subtitle)",
                symbol: "battery.25percent",
                priority: alert.percent <= 5 ? .critical : .important
            ))
        case .charging(let status):
            center.submit(NotchEvent(
                correlationID: "battery:charging",
                source: .battery,
                title: status.title,
                detail: "Battery at \(status.percent)%",
                symbol: "battery.100percent.bolt",
                priority: .normal,
                progress: Double(status.percent) / 100
            ))
        }
    }

    private func ingest(_ presentation: FocusModeController.Presentation?) {
        guard let presentation else {
            center.resolve(source: .focus)
            return
        }
        center.submit(NotchEvent(
            correlationID: "focus:\(presentation.isActive)",
            source: .focus,
            title: presentation.isActive ? "Focus enabled" : "Focus disabled",
            detail: presentation.isActive ? "Distractions are being reduced" : "Notifications are available again",
            symbol: presentation.isActive ? "moon.fill" : "moon",
            priority: .passive
        ))
    }

    private func ingest(_ activity: LiveActivity?) {
        guard let activity else {
            center.resolve(source: .liveActivity)
            return
        }
        center.submit(NotchEvent(
            correlationID: "activity:\(activity.id.uuidString)",
            source: .liveActivity,
            title: activity.title,
            detail: activity.detail,
            symbol: symbol(for: activity.kind),
            priority: .normal,
            progress: activity.progress
        ))
    }

    private func symbol(for kind: LiveActivity.Kind) -> String {
        switch kind {
        case .audioDevice: "airpodspro"
        case .message: "message.fill"
        case .timer: "timer"
        case .download: "arrow.down.circle.fill"
        }
    }
}
