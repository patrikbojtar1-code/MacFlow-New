//
//  MacFlowLogo.swift
//  MacFlow
//
//  Shared production artwork and a dedicated monochrome menu-bar symbol.
//

import AppKit
import SwiftUI

struct MacFlowLogoTile: View {
    var size: CGFloat = 42
    var showsShadow = true

    var body: some View {
        Image("MacFlowBrandIcon")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(
                color: showsShadow ? .black.opacity(0.28) : .clear,
                radius: size * 0.12,
                y: size * 0.07
            )
            .accessibilityHidden(true)
    }
}

/// A compact rendering of the supplied ribbon-M for the system menu bar.
/// The image is a template so macOS controls its color in light, dark, active,
/// disabled, and high-contrast states just like Wi-Fi and Bluetooth.
@MainActor
enum MacFlowMenuBarSymbol {
    static func image() -> NSImage {
        let size = NSSize(width: 22, height: 17)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX + 2.2, y: rect.minY + 2.0))
            path.curve(
                to: NSPoint(x: rect.minX + 6.7, y: rect.maxY - 3.0),
                controlPoint1: NSPoint(x: rect.minX + 2.3, y: rect.minY + 9.5),
                controlPoint2: NSPoint(x: rect.minX + 4.6, y: rect.maxY - 3.0)
            )
            path.curve(
                to: NSPoint(x: rect.midX, y: rect.minY + 6.3),
                controlPoint1: NSPoint(x: rect.minX + 8.3, y: rect.maxY - 3.0),
                controlPoint2: NSPoint(x: rect.midX - 1.6, y: rect.minY + 6.3)
            )
            path.curve(
                to: NSPoint(x: rect.maxX - 6.7, y: rect.maxY - 3.0),
                controlPoint1: NSPoint(x: rect.midX + 1.6, y: rect.minY + 6.3),
                controlPoint2: NSPoint(x: rect.maxX - 8.3, y: rect.maxY - 3.0)
            )
            path.curve(
                to: NSPoint(x: rect.maxX - 2.2, y: rect.minY + 2.0),
                controlPoint1: NSPoint(x: rect.maxX - 4.6, y: rect.maxY - 3.0),
                controlPoint2: NSPoint(x: rect.maxX - 2.3, y: rect.minY + 9.5)
            )
            path.lineWidth = 3.25
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

#Preview {
    ZStack {
        Color.black
        MacFlowLogoTile(size: 160)
    }
    .frame(width: 240, height: 240)
}
