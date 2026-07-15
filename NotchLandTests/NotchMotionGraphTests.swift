//
//  NotchMotionGraphTests.swift
//  NotchLandTests
//

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
}
