//
//  WidgetPreferencesControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct WidgetPreferencesControllerTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WidgetPreferencesControllerTests.\(UUID().uuidString)")!
    }

    @Test func newWidgetsAreEnabledInDefaultOrder() {
        let preferences = WidgetPreferencesController(defaults: makeDefaults())

        #expect(preferences.orderedWidgets == NotchWidget.allCases)
        #expect(preferences.visibleWidgets == NotchWidget.allCases)
    }

    @Test func visibilityAndOrderPersistAcrossRelaunch() {
        let defaults = makeDefaults()
        let preferences = WidgetPreferencesController(defaults: defaults)
        preferences.setEnabled(false, for: .media)
        preferences.move(.mirror, by: -100)

        let restored = WidgetPreferencesController(defaults: defaults)

        #expect(!restored.isEnabled(.media))
        #expect(restored.orderedWidgets.first == .mirror)
        #expect(restored.visibleWidgets.first == .mirror)
    }

    @Test func visibilityModesPersistAndAutomaticRemainsAvailable() {
        let defaults = makeDefaults()
        let preferences = WidgetPreferencesController(defaults: defaults)
        preferences.setMode(.automatic, for: .media)
        preferences.setMode(.hidden, for: .mirror)

        let restored = WidgetPreferencesController(defaults: defaults)

        #expect(restored.mode(for: .media) == .automatic)
        #expect(restored.mode(for: .mirror) == .hidden)
        #expect(restored.visibleWidgets.contains(.media))
        #expect(!restored.visibleWidgets.contains(.mirror))
    }

    @Test func legacyEnabledPreferencesMigrateToVisibilityModes() {
        let defaults = makeDefaults()
        defaults.set([NotchWidget.calendar.rawValue, NotchWidget.files.rawValue], forKey: "widgets.enabled.v1")

        let preferences = WidgetPreferencesController(defaults: defaults)

        #expect(preferences.mode(for: .calendar) == .pinned)
        #expect(preferences.mode(for: .files) == .pinned)
        #expect(preferences.mode(for: .media) == .hidden)
    }

    @Test func atLeastOneWidgetAlwaysRemainsEnabled() {
        let preferences = WidgetPreferencesController(defaults: makeDefaults())
        for widget in NotchWidget.allCases.dropLast() {
            preferences.setEnabled(false, for: widget)
        }
        let finalWidget = NotchWidget.allCases.last!

        preferences.setEnabled(false, for: finalWidget)

        #expect(preferences.visibleWidgets == [finalWidget])
    }

    @Test func movementClampsAtBothEdges() {
        let preferences = WidgetPreferencesController(defaults: makeDefaults())
        let first = preferences.orderedWidgets.first!
        let last = preferences.orderedWidgets.last!

        preferences.move(first, by: -100)
        preferences.move(last, by: 100)

        #expect(preferences.orderedWidgets.first == first)
        #expect(preferences.orderedWidgets.last == last)
    }

    @Test func onboardingConfigurationAppliesOrderAndModes() {
        let preferences = WidgetPreferencesController(defaults: makeDefaults())

        preferences.applyConfiguration(
            preferredOrder: [.wallet, .media, .files],
            pinned: [.wallet, .media],
            automatic: [.files]
        )

        #expect(Array(preferences.orderedWidgets.prefix(3)) == [.wallet, .media, .files])
        #expect(preferences.mode(for: .wallet) == .pinned)
        #expect(preferences.mode(for: .files) == .automatic)
        #expect(preferences.mode(for: .calendar) == .hidden)
    }

    @Test func resetRestoresVisibilityAndCanonicalOrder() {
        let preferences = WidgetPreferencesController(defaults: makeDefaults())
        preferences.setEnabled(false, for: .calendar)
        preferences.move(.tasks, by: -3)

        preferences.reset()

        #expect(preferences.orderedWidgets == NotchWidget.allCases)
        #expect(preferences.visibleWidgets == NotchWidget.allCases)
    }
}
