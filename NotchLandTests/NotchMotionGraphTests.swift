//
//  NotchMotionGraphTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

struct NotchMotionGraphTests {
    @Test func everySemanticRoleHasAMeasuredCurve() {
        #expect(NotchMotionGraph.measurements.count == NotchMotionRole.allCases.count)

        for role in NotchMotionRole.allCases {
            let measurement = NotchMotionGraph.measurement(for: role)
            #expect(measurement.duration >= 0.10)
            #expect(measurement.duration <= 0.55)
            #expect(measurement.delay >= 0)
            #expect(measurement.delay < measurement.duration)
        }
    }

    @Test func springsStayInsideTheProductDampingEnvelope() {
        for measurement in NotchMotionGraph.measurements.values where measurement.curve == .spring {
            let damping = measurement.dampingFraction ?? 0
            #expect(damping >= 0.70)
            #expect(damping <= 0.90)
        }
    }

    @Test func sectionHandoffPreservesVisualCausality() {
        let enter = NotchMotionGraph.measurement(for: .contentEnter)
        let expand = NotchMotionGraph.measurement(for: .containerExpand)
        let dismiss = NotchMotionGraph.measurement(for: .dismiss)
        let returning = NotchMotionGraph.measurement(for: .contentReturn)

        #expect(NotchMotionGraph.compressDuration < expand.duration)
        #expect(NotchMotionGraph.handoffDelay <= 1.0 / 60.0)
        #expect(enter.delay > NotchMotionGraph.handoffDelay)
        #expect(dismiss.duration < expand.duration)
        #expect(returning.duration >= expand.duration)
    }

    @Test func reducedMotionIsFastAndAmbientCadenceIsSlowerThanInteraction() {
        #expect(NotchMotionGraph.reduced.duration <= 0.10)
        #expect(NotchAmbientMotion.pulseDuration > NotchMotionGraph.measurement(for: .selection).duration)
        #expect(NotchAmbientMotion.orbitDuration > NotchMotionGraph.measurement(for: .containerExpand).duration)
        #expect(NotchAmbientMotion.spinnerDuration > NotchMotionGraph.measurement(for: .hover).duration)
    }

    @MainActor
    @Test func motionDebuggerExplainsInterruptionsAndCountsSurfaceRedraws() {
        let suite = "MotionDebugStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MotionDebugStore(defaults: defaults, enabled: true)

        store.record(
            name: "notch.presentation",
            surface: "Notch Shell",
            duration: 1,
            state: "media → expanded",
            reason: "User expanded the notch."
        )
        store.markRender(surface: "Notch Shell")
        store.record(
            name: "notch.presentation",
            surface: "Notch Shell",
            duration: 1,
            state: "expanded → call",
            reason: "Incoming call interrupted media."
        )

        #expect(store.activeEvents.count == 1)
        #expect(store.events.contains { $0.phase == .interrupted && $0.redrawCount == 1 })
        #expect(store.events.first?.reason == "Incoming call interrupted media.")
        store.clear()
    }
}
