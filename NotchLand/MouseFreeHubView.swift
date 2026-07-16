//
//  MouseFreeHubView.swift
//  MacFlow
//
//  Integrated MouseFree control surface backed by the real scroll interceptor.
//

import AppKit
import SwiftUI

struct MouseFreeHubView: View {
    @EnvironmentObject private var controller: MouseFreeController

    private enum Metrics {
        static let previewHeight: CGFloat = 138
        static let presetMinimumWidth: CGFloat = 150
        static let statusIconSize: CGFloat = 52
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacFlowMetrics.sectionSpacing) {
                hero

                if controller.isEnabled, !controller.isAccessibilityTrusted {
                    permissionCard
                }

                curvePreview
                presets
                tuning
                behavior
            }
            .padding(MacFlowMetrics.detailPadding)
        }
        .onAppear { controller.refreshPermissionStatus() }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: Metrics.statusIconSize, height: Metrics.statusIconSize)

            VStack(alignment: .leading, spacing: 3) {
                Text("MouseFree")
                    .font(.title2.weight(.semibold))
                Text("Frame-synchronised scrolling for external mouse wheels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(controller.status.title, systemImage: controller.status.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(statusColor.opacity(0.1), in: Capsule())

            Toggle("Enable MouseFree", isOn: $controller.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var permissionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.13))
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(permissionTitle)
                    .font(.headline)
                Text(permissionExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if controller.isStableApplicationLocation {
                Button("Allow MacFlow") { controller.requestAccessibilityPermission() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Show Build") { revealCurrentApplication() }
                    .buttonStyle(.borderedProminent)
            }
            Button("Open Settings") { openAccessibilitySettings() }
                .buttonStyle(.bordered)
        }
        .padding(MacFlowMetrics.cardPadding)
        .background(
            Color.orange.opacity(0.055),
            in: RoundedRectangle(cornerRadius: MacFlowMetrics.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowMetrics.cardRadius, style: .continuous)
                .stroke(.orange.opacity(0.18), lineWidth: 1)
        }
    }

    private var curvePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scroll Response")
                        .font(.headline)
                    Text("The curve updates with your current speed, smoothness, and acceleration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(controller.selectedPreset?.title ?? "Custom")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.1), in: Capsule())
            }

            MouseScrollCurvePreview(
                speed: controller.speed,
                smoothness: controller.smoothness,
                acceleration: controller.acceleration
            )
            .frame(height: Metrics.previewHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mouse scroll response curve")
        }
        .padding(MacFlowMetrics.cardPadding)
        .background(
            MacFlowTheme.cardSurface,
            in: RoundedRectangle(cornerRadius: MacFlowMetrics.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowMetrics.cardRadius, style: .continuous)
                .stroke(MacFlowTheme.subtleStroke, lineWidth: 1)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Feel Presets")
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Metrics.presetMinimumWidth), spacing: 10)],
                spacing: 10
            ) {
                ForEach(MouseScrollPreset.allCases) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    private func presetButton(_ preset: MouseScrollPreset) -> some View {
        let isSelected = controller.selectedPreset == preset
        return Button {
            NotchHaptics.perform(.navigation)
            controller.apply(preset)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.orange.opacity(isSelected ? 0.18 : 0.08))
                    Image(systemName: isSelected ? "checkmark" : "waveform.path")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isSelected ? .orange : .secondary)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.callout.weight(.semibold))
                    Text(preset.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(
                isSelected ? Color.orange.opacity(0.08) : MacFlowTheme.cardSurface,
                in: RoundedRectangle(cornerRadius: MacFlowMetrics.compactCardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacFlowMetrics.compactCardRadius, style: .continuous)
                    .stroke(isSelected ? .orange.opacity(0.28) : MacFlowTheme.subtleStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var tuning: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fine Tuning")
                .font(.headline)
            tuningSlider(
                title: "Speed",
                detail: controller.speed.formatted(.number.precision(.fractionLength(2))),
                value: $controller.speed,
                range: 0.5...3
            )
            tuningSlider(
                title: "Smoothness",
                detail: controller.smoothness.formatted(.percent.precision(.fractionLength(0))),
                value: $controller.smoothness,
                range: 0...1
            )
            tuningSlider(
                title: "Acceleration",
                detail: controller.acceleration.formatted(.percent.precision(.fractionLength(0))),
                value: $controller.acceleration,
                range: 0...1
            )
        }
        .padding(MacFlowMetrics.cardPadding)
        .background(
            MacFlowTheme.cardSurface,
            in: RoundedRectangle(cornerRadius: MacFlowMetrics.cardRadius, style: .continuous)
        )
    }

    private func tuningSlider(
        title: String,
        detail: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text(detail)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(.orange)
        }
    }

    private var behavior: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Behavior")
                .font(.headline)
            Toggle("Reverse wheel direction", isOn: $controller.reverseScroll)
            Toggle("Hold Option to bypass MouseFree", isOn: $controller.optionBypassEnabled)
            Divider()
            Label(
                "Trackpads and Magic Mouse keep their native macOS momentum.",
                systemImage: "hand.point.up.left.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(MacFlowMetrics.cardPadding)
        .background(
            MacFlowTheme.cardSurface,
            in: RoundedRectangle(cornerRadius: MacFlowMetrics.cardRadius, style: .continuous)
        )
    }

    private var statusColor: Color {
        switch controller.status {
        case .active: .green
        case .needsAccessibility: .orange
        case .disabled: .secondary
        case .unavailable: .red
        }
    }

    private var permissionTitle: String {
        controller.isStableApplicationLocation
            ? "Accessibility permission required"
            : "Install this MacFlow build first"
    }

    private var permissionExplanation: String {
        if controller.isStableApplicationLocation {
            return "MacFlow needs permission only to replace stepped wheel events with smooth pixel movement."
        }
        return "This copy is running outside Applications. macOS gives each temporary build a different identity, so the enabled NotchLand entry belongs to another copy."
    }

    private func revealCurrentApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct MouseScrollCurvePreview: View {
    let speed: Double
    let smoothness: Double
    let acceleration: Double

    var body: some View {
        Canvas { context, size in
            let baseline = size.height * 0.82
            let amplitude = size.height * (0.34 + smoothness * 0.28)
            let peakX = size.width * (0.18 + acceleration * 0.12)
            let tailX = size.width * (0.70 + smoothness * 0.24)

            var grid = Path()
            for index in 0...4 {
                let y = size.height * CGFloat(index) / 4
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.05)), lineWidth: 1)

            var area = Path()
            area.move(to: CGPoint(x: 0, y: baseline))
            area.addCurve(
                to: CGPoint(x: peakX, y: baseline - amplitude),
                control1: CGPoint(x: peakX * 0.30, y: baseline),
                control2: CGPoint(x: peakX * 0.55, y: baseline - amplitude)
            )
            area.addCurve(
                to: CGPoint(x: tailX, y: baseline - 2),
                control1: CGPoint(x: peakX + size.width * 0.18, y: baseline - amplitude * speed / 1.2),
                control2: CGPoint(x: tailX - size.width * 0.22, y: baseline - 3)
            )
            area.addLine(to: CGPoint(x: size.width, y: baseline))

            var fill = area
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [.orange.opacity(0.28), .orange.opacity(0.01)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(area, with: .color(.orange.opacity(0.9)), lineWidth: 2.2)
        }
    }
}
