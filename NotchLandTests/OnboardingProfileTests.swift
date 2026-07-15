//
//  OnboardingProfileTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct OnboardingProfileTests {
    private func makePreferences() -> WidgetPreferencesController {
        let defaults = UserDefaults(suiteName: "OnboardingProfileTests.\(UUID().uuidString)")!
        return WidgetPreferencesController(defaults: defaults)
    }

    @Test func productivityPresetPrioritizesPlanningModules() {
        let preferences = makePreferences()

        OnboardingProfile.productivity.apply(to: preferences)

        #expect(Array(preferences.orderedWidgets.prefix(4)) == [.calendar, .tasks, .notes, .timer])
        #expect(preferences.mode(for: .calendar) == .pinned)
        #expect(preferences.mode(for: .files) == .automatic)
        #expect(preferences.mode(for: .mirror) == .hidden)
    }

    @Test func creatorPresetPrioritizesWalletAndMedia() {
        let preferences = makePreferences()

        OnboardingProfile.creator.apply(to: preferences)

        #expect(Array(preferences.orderedWidgets.prefix(4)) == [.wallet, .media, .files, .actions])
        #expect(preferences.mode(for: .wallet) == .pinned)
        #expect(preferences.mode(for: .calendar) == .automatic)
        #expect(preferences.mode(for: .tasks) == .hidden)
    }

    @Test func minimalPresetKeepsACompactVisibleSet() {
        let preferences = makePreferences()

        OnboardingProfile.minimal.apply(to: preferences)

        #expect(preferences.pinnedWidgets == [.media, .calendar, .files])
        #expect(preferences.visibleWidgets.count == 6)
        #expect(preferences.mode(for: .wallet) == .automatic)
    }

    @Test func customPresetPreservesExistingConfiguration() {
        let preferences = makePreferences()
        preferences.setMode(.hidden, for: .mirror)
        let orderBefore = preferences.orderedWidgets
        let modesBefore = preferences.visibilityModes

        OnboardingProfile.custom.apply(to: preferences)

        #expect(preferences.orderedWidgets == orderBefore)
        #expect(preferences.visibilityModes == modesBefore)
    }
}
