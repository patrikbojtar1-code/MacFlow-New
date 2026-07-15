//
//  NotchTimerController.swift
//  NotchLand
//
//  Persistent timer state machine shared by the expanded Timer widget and the
//  compact Live Activity. The absolute end date keeps countdowns accurate
//  through sleep, wake and application relaunches.
//

import AppKit
import Combine
import Foundation

@MainActor
final class NotchTimerController: ObservableObject {
    enum State: String, Codable, Equatable {
        case idle
        case running
        case paused
        case finished
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var endDate: Date?
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private enum Keys {
        static let state = "notchTimer.state"
        static let endDate = "notchTimer.endDate"
        static let remaining = "notchTimer.remaining"
        static let duration = "notchTimer.duration"
    }

    private let activities: LiveActivityController
    private let defaults: UserDefaults
    private var activityID = UUID()
    private var tick: Task<Void, Never>?

    init(activities: LiveActivityController, defaults: UserDefaults = .standard) {
        self.activities = activities
        self.defaults = defaults
        restore()
    }

    var isRunning: Bool { state == .running }
    var canPause: Bool { state == .running }
    var canResume: Bool { state == .paused && remaining > 0 }

    func start(minutes: Int) {
        start(duration: TimeInterval(max(1, minutes) * 60))
    }

    func start(duration newDuration: TimeInterval) {
        guard newDuration > 0 else { return }
        stopTicking()
        duration = newDuration
        remaining = newDuration
        endDate = Date.now.addingTimeInterval(newDuration)
        state = .running
        activityID = UUID()
        persist()
        postChip(remaining: newDuration)
        startTicking()
        NotchHaptics.perform(.confirmation)
    }

    func pause() {
        guard state == .running else { return }
        remaining = currentRemaining()
        endDate = nil
        state = .paused
        stopTicking()
        activities.end(activityID)
        persist()
        NotchHaptics.perform(.navigation)
    }

    func resume() {
        guard canResume else { return }
        endDate = Date.now.addingTimeInterval(remaining)
        state = .running
        activityID = UUID()
        persist()
        postChip(remaining: remaining)
        startTicking()
        NotchHaptics.perform(.navigation)
    }

    func reset() {
        stopTicking()
        activities.end(activityID)
        state = .idle
        endDate = nil
        remaining = 0
        duration = 0
        persist()
    }

    func cancel() {
        reset()
    }

    /// Stops the in-process ticker while preserving the absolute end date for
    /// the next launch. Used during normal application termination.
    func suspend() {
        stopTicking()
    }

    func currentRemaining(at date: Date = .now) -> TimeInterval {
        if state == .running, let endDate {
            return max(0, endDate.timeIntervalSince(date))
        }
        return max(0, remaining)
    }

    func progress(at date: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - currentRemaining(at: date) / duration))
    }

    private func startTicking() {
        stopTicking()
        tick = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .running else { return }
                let value = self.currentRemaining()
                self.remaining = value
                if value <= 0 {
                    self.finish()
                    return
                }
                self.postChip(remaining: value)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTicking() {
        tick?.cancel()
        tick = nil
    }

    private func postChip(remaining: TimeInterval) {
        let total = Int(remaining.rounded(.up))
        let detail = String(format: "%d:%02d", total / 60, total % 60)
        activities.post(LiveActivity(
            id: activityID,
            kind: .timer(remaining: remaining),
            title: "Timer",
            detail: detail,
            progress: duration > 0 ? 1 - remaining / duration : nil
        ))
    }

    private func finish() {
        stopTicking()
        remaining = 0
        endDate = nil
        state = .finished
        persist()

        let finishedID = activityID
        activities.post(LiveActivity(
            id: finishedID,
            kind: .timer(remaining: 0),
            title: "Time's up",
            detail: nil,
            progress: 1
        ))
        NSSound(named: "Glass")?.play()
        NotchHaptics.perform(.confirmation)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.activities.end(finishedID)
        }
    }

    private func restore() {
        duration = defaults.double(forKey: Keys.duration)
        remaining = defaults.double(forKey: Keys.remaining)
        state = State(rawValue: defaults.string(forKey: Keys.state) ?? "") ?? .idle
        endDate = defaults.object(forKey: Keys.endDate) as? Date

        switch state {
        case .running:
            guard let endDate else {
                state = .idle
                persist()
                return
            }
            remaining = max(0, endDate.timeIntervalSinceNow)
            if remaining > 0 {
                activityID = UUID()
                postChip(remaining: remaining)
                startTicking()
            } else {
                state = .finished
                self.endDate = nil
                persist()
            }
        case .paused:
            endDate = nil
        case .idle, .finished:
            endDate = nil
        }
    }

    private func persist() {
        defaults.set(state.rawValue, forKey: Keys.state)
        defaults.set(endDate, forKey: Keys.endDate)
        defaults.set(remaining, forKey: Keys.remaining)
        defaults.set(duration, forKey: Keys.duration)
    }
}
