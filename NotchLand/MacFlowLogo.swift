//
//  MacFlowLogo.swift
//  MacFlow
//
//  Original, scalable MacFlow brand mark shared by the app shell and icon.
//

import SwiftUI

struct MacFlowLogoTile: View {
    var size: CGFloat = 42
    var showsShadow = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.265, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.055, green: 0.075, blue: 0.14),
                            Color(red: 0.10, green: 0.09, blue: 0.24),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.265, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
            MacFlowMark()
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .shadow(
            color: showsShadow ? Color(red: 0.26, green: 0.35, blue: 1).opacity(0.24) : .clear,
            radius: size * 0.22,
            y: size * 0.09
        )
        .accessibilityHidden(true)
    }
}

struct MacFlowMark: View {
    var body: some View {
        GeometryReader { proxy in
            let lineWidth = max(2, proxy.size.width * 0.145)

            ZStack {
                MacFlowRibbonShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.29, green: 0.91, blue: 1),
                                Color(red: 0.48, green: 0.55, blue: 1),
                                Color(red: 0.76, green: 0.39, blue: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                Circle()
                    .fill(.white)
                    .frame(width: lineWidth * 0.48, height: lineWidth * 0.48)
                    .offset(y: proxy.size.height * 0.27)
                    .shadow(color: .white.opacity(0.55), radius: lineWidth * 0.22)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct MacFlowRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.12, y: h * 0.68))
        path.addCurve(
            to: CGPoint(x: w * 0.42, y: h * 0.39),
            control1: CGPoint(x: w * 0.12, y: h * 0.31),
            control2: CGPoint(x: w * 0.31, y: h * 0.24)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.53),
            control1: CGPoint(x: w * 0.46, y: h * 0.44),
            control2: CGPoint(x: w * 0.48, y: h * 0.50)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.58, y: h * 0.39),
            control1: CGPoint(x: w * 0.52, y: h * 0.50),
            control2: CGPoint(x: w * 0.54, y: h * 0.44)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.68),
            control1: CGPoint(x: w * 0.69, y: h * 0.24),
            control2: CGPoint(x: w * 0.88, y: h * 0.31)
        )
        return path
    }
}

#Preview {
    ZStack {
        Color.black
        MacFlowLogoTile(size: 160)
    }
    .frame(width: 240, height: 240)
}
