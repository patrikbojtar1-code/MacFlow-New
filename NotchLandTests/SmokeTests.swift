//
//  SmokeTests.swift
//  NotchLandTests
//
//  Verifies the test target links against the app module.
//

import Testing
@testable import NotchLand

struct SmokeTests {
    @Test func smoke() {
        #expect(NotchSettings.Defaults.showNotch == true)
    }

    @MainActor
    @Test func appStateCarriesARequestedSiriModuleUntilConsumed() {
        let state = AppState(settings: NotchSettings())

        state.requestOpenWidget(rawValue: NotchWidget.timer.rawValue)
        #expect(state.requestedWidgetRawValue == NotchWidget.timer.rawValue)
        #expect(state.isExpanded)

        state.consumeRequestedWidget()
        #expect(state.requestedWidgetRawValue == nil)
    }
}
