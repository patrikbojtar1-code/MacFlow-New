//
//  HUDBarView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Renders the level HUD as a compact icon + filled bar, sized
//  to sit in the drawer below the collapsed notch.
//

import SwiftUI

struct HUDBarView: View {
    let kind: HUDController.Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.16))
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 28, height: 28)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.13))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, geo.size.width * clampedLevel))
                        .shadow(color: accent.opacity(0.28), radius: 3)
                        .animation(AppMotion.stateChange(reduceMotion: reduceMotion), value: clampedLevel)
                }
            }
            .frame(height: 6)

            Text(valueLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: HUDController.drawerHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(valueLabel)
    }

    private var iconName: String {
        switch kind {
        case .volume(_, let muted):
            muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness:
            "sun.max.fill"
        case .keyboardBrightness:
            "keyboard"
        case .contrast:
            "circle.lefthalf.filled"
        }
    }

    private var level: Double {
        switch kind {
        case .volume(let l, let muted): muted ? 0 : l
        case .brightness(let l): l
        case .keyboardBrightness(let l): l
        case .contrast(let l): l
        }
    }

    private var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    private var accent: Color {
        switch kind {
        case .volume(_, let muted): muted ? .secondary : Color(red: 0.34, green: 0.68, blue: 1)
        case .brightness: Color(red: 1, green: 0.72, blue: 0.24)
        case .keyboardBrightness: Color(red: 0.68, green: 0.58, blue: 1)
        case .contrast: .white
        }
    }

    private var valueLabel: String {
        if case .volume(_, let muted) = kind, muted { return "Muted" }
        return "\(Int((clampedLevel * 100).rounded()))%"
    }

    private var accessibilityTitle: String {
        switch kind {
        case .volume: "Volume"
        case .brightness: "Display brightness"
        case .keyboardBrightness: "Keyboard brightness"
        case .contrast: "Contrast"
        }
    }
}

#if DEBUG
#Preview("Volume HUD") {
    HUDBarView(kind: .volume(level: 0.72, muted: false))
        .notchPreviewSurface(width: 280, height: HUDController.drawerHeight)
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
