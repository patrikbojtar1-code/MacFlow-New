//
//  MouseFreeScrollEngine.swift
//  MacFlow
//
//  Refresh-rate independent momentum model migrated from MouseFree.
//

import Foundation

nonisolated struct MouseScrollConfiguration: Equatable, Sendable {
    var speed: Double
    var smoothness: Double
    var acceleration: Double

    var impulseStrength: Double { 620 * speed }
    var responseRate: Double { 34 - smoothness * 12 }
    var inputDecayRate: Double { 18 - smoothness * 10 }
    var frictionRate: Double { 15 - smoothness * 10.5 }
    var maximumVelocity: Double { 2_400 + speed * 1_600 + acceleration * 2_600 }
}

nonisolated struct MouseScrollFrame: Equatable, Sendable {
    let x: Int32
    let y: Int32

    var isEmpty: Bool { x == 0 && y == 0 }
}

nonisolated final class MouseFreeScrollEngine: @unchecked Sendable {
    private struct AxisState {
        var targetVelocity = 0.0
        var velocity = 0.0
        var remainder = 0.0

        var isSettled: Bool {
            abs(targetVelocity) < 0.4 && abs(velocity) < 0.4
        }

        mutating func reset() {
            targetVelocity = 0
            velocity = 0
            remainder = 0
        }
    }

    private var horizontal = AxisState()
    private var vertical = AxisState()
    private var lastInputTimestamp: TimeInterval?

    var isAnimating: Bool {
        !horizontal.isSettled || !vertical.isSettled
    }

    func addInput(
        x: Double,
        y: Double,
        timestamp: TimeInterval,
        configuration: MouseScrollConfiguration
    ) {
        let interval = lastInputTimestamp.map { max(timestamp - $0, 0) }
        lastInputTimestamp = timestamp

        if let interval, interval > 0.18 {
            horizontal.targetVelocity = 0
            vertical.targetVelocity = 0
            horizontal.velocity *= 0.28
            vertical.velocity *= 0.28
        }

        let cadence = interval.map { max(0, 1 - $0 / 0.095) } ?? 0
        let magnitude = max(abs(x), abs(y))
        let magnitudeBoost = min(max(magnitude - 1, 0) * 0.08, 0.7)
        let accelerationBoost = 1 + configuration.acceleration * (cadence * 1.55 + magnitudeBoost)

        addImpulse(
            x * configuration.impulseStrength * accelerationBoost,
            to: &horizontal,
            maximumVelocity: configuration.maximumVelocity
        )
        addImpulse(
            y * configuration.impulseStrength * accelerationBoost,
            to: &vertical,
            maximumVelocity: configuration.maximumVelocity
        )
    }

    func update(
        deltaTime: TimeInterval,
        configuration: MouseScrollConfiguration
    ) -> MouseScrollFrame? {
        guard isAnimating else { return nil }

        let delta = min(max(deltaTime, 1.0 / 240.0), 1.0 / 30.0)
        let response = 1 - exp(-configuration.responseRate * delta)
        let targetDecay = exp(-configuration.inputDecayRate * delta)
        let velocityDecay = exp(-configuration.frictionRate * delta)

        let x = updateAxis(
            &horizontal,
            deltaTime: delta,
            response: response,
            targetDecay: targetDecay,
            velocityDecay: velocityDecay
        )
        let y = updateAxis(
            &vertical,
            deltaTime: delta,
            response: response,
            targetDecay: targetDecay,
            velocityDecay: velocityDecay
        )

        let frame = MouseScrollFrame(x: x, y: y)
        return frame.isEmpty ? nil : frame
    }

    func reset() {
        horizontal.reset()
        vertical.reset()
        lastInputTimestamp = nil
    }

    private func addImpulse(
        _ impulse: Double,
        to state: inout AxisState,
        maximumVelocity: Double
    ) {
        guard impulse != 0 else { return }
        if state.velocity * impulse < 0 || state.targetVelocity * impulse < 0 {
            state.velocity *= 0.10
            state.targetVelocity = 0
            state.remainder = 0
        }
        state.targetVelocity = clamp(
            state.targetVelocity + impulse,
            minimum: -maximumVelocity,
            maximum: maximumVelocity
        )
    }

    private func updateAxis(
        _ state: inout AxisState,
        deltaTime: TimeInterval,
        response: Double,
        targetDecay: Double,
        velocityDecay: Double
    ) -> Int32 {
        state.velocity += (state.targetVelocity - state.velocity) * response
        state.targetVelocity *= targetDecay
        state.velocity *= velocityDecay

        let movement = state.velocity * deltaTime + state.remainder
        let emitted = Int32(
            clamp(
                movement.rounded(.towardZero),
                minimum: Double(Int32.min),
                maximum: Double(Int32.max)
            )
        )
        state.remainder = movement - Double(emitted)

        if abs(state.targetVelocity) < 0.4 { state.targetVelocity = 0 }
        if abs(state.velocity) < 0.4 { state.velocity = 0 }
        if state.isSettled { state.remainder = 0 }
        return emitted
    }

    private func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}
