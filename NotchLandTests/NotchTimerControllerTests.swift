//
//  NotchTimerControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct NotchTimerControllerTests {
    private func makeSystem() -> (
        timer: NotchTimerController,
        activities: LiveActivityController,
        defaults: UserDefaults
    ) {
        let defaults = UserDefaults(suiteName: "NotchTimerControllerTests.\(UUID().uuidString)")!
        let settings = NotchSettings()
        settings.liveActivitiesEnabled = true
        let activities = LiveActivityController(settings: settings)
        return (
            NotchTimerController(activities: activities, defaults: defaults),
            activities,
            defaults
        )
    }

    @Test func startPublishesRunningTimerAndLiveActivity() {
        let system = makeSystem()
        system.timer.start(duration: 120)
        defer { system.timer.reset() }

        #expect(system.timer.state == .running)
        #expect(system.timer.currentRemaining() > 119)
        #expect(system.timer.duration == 120)
        #expect(system.activities.current?.title == "Timer")
    }

    @Test func pauseAndResumePreserveRemainingTime() {
        let system = makeSystem()
        system.timer.start(duration: 90)
        system.timer.pause()
        let pausedRemaining = system.timer.remaining

        #expect(system.timer.state == .paused)
        #expect(system.timer.endDate == nil)
        #expect(system.activities.current == nil)

        system.timer.resume()
        defer { system.timer.reset() }

        #expect(system.timer.state == .running)
        #expect(system.timer.currentRemaining() <= pausedRemaining)
        #expect(system.timer.currentRemaining() > pausedRemaining - 1)
    }

    @Test func runningTimerRestoresFromAbsoluteEndDate() {
        let system = makeSystem()
        system.timer.start(duration: 180)
        system.timer.suspend()

        let restored = NotchTimerController(
            activities: system.activities,
            defaults: system.defaults
        )
        defer { restored.reset() }

        #expect(restored.state == .running)
        #expect(restored.currentRemaining() > 179)
        #expect(restored.duration == 180)
    }

    @Test func resetClearsPersistedTimer() {
        let system = makeSystem()
        system.timer.start(duration: 60)
        system.timer.reset()

        let restored = NotchTimerController(
            activities: system.activities,
            defaults: system.defaults
        )

        #expect(restored.state == .idle)
        #expect(restored.remaining == 0)
        #expect(restored.duration == 0)
        #expect(restored.endDate == nil)
    }
}
