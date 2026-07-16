//
//  AppMotion.swift
//  MacFlow
//
//  Small, semantic motion vocabulary for the MacFlow application shell.
//

import SwiftUI

nonisolated enum AppMotion {
    enum Duration {
        static let instant: TimeInterval = 0.10
        static let quick: TimeInterval = 0.16
        static let standard: TimeInterval = 0.22
        static let emphasized: TimeInterval = 0.34
    }

    static func stateChange(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? Duration.instant : Duration.standard)
    }

    static func insertion(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? Duration.instant : Duration.standard)
    }

    static func removal(reduceMotion: Bool) -> Animation {
        .easeIn(duration: reduceMotion ? Duration.instant : Duration.quick)
    }

    static func interaction(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: Duration.instant)
            : .spring(response: Duration.standard, dampingFraction: 0.92, blendDuration: 0)
    }

    static func emphasized(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: Duration.instant)
            : .spring(response: Duration.emphasized, dampingFraction: 0.94, blendDuration: 0)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity
        )
    }

    static func directionalTransition(reduceMotion: Bool, forward: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 8 : -8)),
            removal: .opacity
        )
    }
}
