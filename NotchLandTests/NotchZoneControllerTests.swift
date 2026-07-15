//
//  NotchZoneControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct NotchZoneControllerTests {
    @Test func physicalNotchSafeGeometryMapsThreeZones() {
        let totalWidth: CGFloat = 323
        let hardwareWidth: CGFloat = 189

        #expect(NotchZoneLayout.sideWidth(totalWidth: totalWidth, hardwareWidth: hardwareWidth) == 67)
        #expect(NotchZoneLayout.zone(at: 20, totalWidth: totalWidth, hardwareWidth: hardwareWidth) == .timeline)
        #expect(NotchZoneLayout.zone(at: 160, totalWidth: totalWidth, hardwareWidth: hardwareWidth) == .center)
        #expect(NotchZoneLayout.zone(at: 310, totalWidth: totalWidth, hardwareWidth: hardwareWidth) == .shortcuts)
    }

    @Test func intentionalHoverRevealsZonesAfterDelay() async {
        let controller = NotchZoneController(revealDelay: .milliseconds(10))

        controller.update(isHovering: true, isEligible: true, reduceMotion: false)
        #expect(controller.phase == .armed)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(controller.phase == .visible)
    }

    @Test func fastPointerExitCancelsPendingReveal() async {
        let controller = NotchZoneController(revealDelay: .milliseconds(20))
        controller.update(isHovering: true, isEligible: true, reduceMotion: false)

        controller.update(isHovering: false, isEligible: true, reduceMotion: false)
        try? await Task.sleep(for: .milliseconds(35))

        #expect(controller.phase == .hidden)
    }

    @Test func blockedContextNeverShowsZones() async {
        let controller = NotchZoneController(revealDelay: .zero)

        controller.update(isHovering: true, isEligible: false, reduceMotion: false)
        await Task.yield()

        #expect(controller.phase == .hidden)
    }

    @Test func reducedMotionRevealsWithoutAnimatedDelay() async {
        let controller = NotchZoneController(revealDelay: .seconds(1))

        controller.update(isHovering: true, isEligible: true, reduceMotion: true)
        try? await Task.sleep(for: .milliseconds(10))

        #expect(controller.phase == .visible)
    }
}
