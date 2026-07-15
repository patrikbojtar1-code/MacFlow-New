//
//  ScreenLockControllerTests.swift
//  NotchLandTests
//

import Testing
@testable import NotchLand

@MainActor
struct ScreenLockControllerTests {
    @Test func repeatedLockLifecycleCanForceAWindowReattach() {
        let controller = ScreenLockController(settings: NotchSettings())

        controller.debugShowLock()
        let firstRevision = controller.lifecycleRevision
        controller.debugShowLock()

        #expect(controller.currentPresentation?.phase == .locked)
        #expect(controller.lifecycleRevision == firstRevision + 1)
    }

    @Test func unlockChangesPhaseAndAdvancesLifecycle() {
        let controller = ScreenLockController(settings: NotchSettings())
        controller.debugShowLock()
        let lockRevision = controller.lifecycleRevision

        controller.debugShowUnlock()

        #expect(controller.currentPresentation?.phase == .unlocking)
        #expect(controller.lifecycleRevision == lockRevision + 1)
    }
}
