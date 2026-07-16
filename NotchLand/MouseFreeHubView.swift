//
//  MouseFreeHubView.swift
//  MacFlow
//
//  Precision tuning workspace backed by the real scroll interceptor.
//

import AppKit
import SwiftUI

struct MouseFreeHubView: View {
    @EnvironmentObject private var controller: MouseFreeController

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(
                eyebrow: "Scroll tuning",
                title: "MouseFree"
            ) {
                HStack(spacing: MacFlowSpacing.space12) {
                    MacFlowStatusPill(
                        title: controller.status.title,
                        systemImage: controller.status.systemImage,
                        color: statusColor
                    )
                    Toggle("Enable MouseFree", isOn: $controller.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            Divider().overlay(MacFlowColor.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space16) {
                    if controller.isEnabled, !controller.isAccessibilityTrusted {
                        permissionRow
                    }

                    responsePanel
                    presetStrip

                    HStack(alignment: .top, spacing: MacFlowSpacing.space12) {
                        fineTuning.frame(maxWidth: .infinity)
                        behavior.frame(width: 260)
                    }
                }
                .padding(MacFlowSpacing.space24)
                .frame(maxWidth: MacFlowMetrics.readableContentMaxWidth)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { controller.refreshPermissionStatus() }
    }

    private var permissionRow: some View {
        MacFlowPanel(.grouped) {
            HStack(spacing: MacFlowSpacing.space12) {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text(permissionTitle)
                        .font(.system(size: 13, weight: .medium))
                }

                Spacer(minLength: MacFlowSpacing.space16)

                if controller.isStableApplicationLocation {
                    Button(controller.hasRequestedAccessibilityThisRun ? "Open Settings" : "Allow") {
                        if controller.hasRequestedAccessibilityThisRun {
                            openAccessibilitySettings()
                        } else {
                            controller.requestAccessibilityPermission()
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(MacFlowColor.accent)
                } else {
                    Button("Show Build") { revealCurrentApplication() }
                        .buttonStyle(.borderedProminent)
                        .tint(MacFlowColor.accent)
                }
                Button { openAccessibilitySettings() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .help("Open Accessibility Settings")
                .accessibilityLabel("Open Accessibility Settings")
            }
            .padding(MacFlowSpacing.space12)
        }
    }

    private var responsePanel: some View {
        MacFlowPanel(.elevated) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Scroll response")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(controller.selectedPreset?.title ?? "Custom")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MacFlowColor.mouseFree)
                        .padding(.horizontal, MacFlowSpacing.space12)
                        .padding(.vertical, MacFlowSpacing.space8)
                        .background(MacFlowColor.mouseFree.opacity(0.09), in: Capsule())
                }

                MouseFreeResponseChart(
                    speed: controller.speed,
                    smoothness: controller.smoothness,
                    acceleration: controller.acceleration
                )
                .frame(height: 132)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("MouseFree response curve")
                .accessibilityValue(controller.selectedPreset?.title ?? "Custom response")
            }
            .padding(MacFlowSpacing.space12)
        }
    }

    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Presets")
            HStack(spacing: MacFlowSpacing.space8) {
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
            HStack(spacing: MacFlowSpacing.space12) {
                Image(systemName: isSelected ? "checkmark" : "waveform.path")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? MacFlowColor.mouseFree : MacFlowColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        isSelected ? MacFlowColor.mouseFree.opacity(0.11) : MacFlowColor.surface1,
                        in: Circle()
                    )
                Text(preset.title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacFlowSpacing.space12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isSelected ? MacFlowColor.surface2 : MacFlowColor.surface1,
                in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                    .stroke(isSelected ? MacFlowColor.mouseFree.opacity(0.42) : MacFlowColor.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fineTuning: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Fine tuning")
            MacFlowPanel(.grouped) {
                VStack(spacing: 0) {
                    tuningRow(
                        title: "Speed",
                        detail: "Overall scroll distance",
                        value: $controller.speed,
                        range: 0.5...3,
                        valueText: controller.speed.formatted(.number.precision(.fractionLength(2)))
                    )
                    MacFlowInsetDivider(leading: MacFlowSpacing.space16)
                    tuningRow(
                        title: "Smoothness",
                        detail: "Length of the momentum tail",
                        value: $controller.smoothness,
                        range: 0...1,
                        valueText: controller.smoothness.formatted(.percent.precision(.fractionLength(0)))
                    )
                    MacFlowInsetDivider(leading: MacFlowSpacing.space16)
                    tuningRow(
                        title: "Acceleration",
                        detail: "Response to faster wheel input",
                        value: $controller.acceleration,
                        range: 0...1,
                        valueText: controller.acceleration.formatted(.percent.precision(.fractionLength(0)))
                    )
                }
                .padding(.vertical, MacFlowSpacing.space4)
            }
        }
    }

    private func tuningRow(
        title: String,
        detail: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        HStack(spacing: MacFlowSpacing.space16) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .frame(width: 86, alignment: .leading)

            Slider(value: value, in: range)
                .tint(MacFlowColor.mouseFree)

            Text(valueText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(MacFlowColor.textSecondary)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, MacFlowSpacing.space12)
        .frame(minHeight: 50)
    }

    private var behavior: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            MacFlowSectionHeader("Behavior")
            MacFlowSettingsGroup {
                compactToggle(
                    title: "Reverse direction",
                    binding: $controller.reverseScroll
                )
                MacFlowInsetDivider(leading: MacFlowSpacing.space16)
                compactToggle(
                    title: "Option bypass",
                    binding: $controller.optionBypassEnabled
                )
                MacFlowInsetDivider(leading: MacFlowSpacing.space16)
                Label("Trackpads stay native", systemImage: "hand.point.up.left.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(MacFlowColor.textSecondary)
                    .padding(MacFlowSpacing.space12)
            }
        }
    }

    private func compactToggle(title: String, binding: Binding<Bool>) -> some View {
        HStack(spacing: MacFlowSpacing.space12) {
            Text(title).font(.system(size: 11.5, weight: .medium))
            Spacer()
            Toggle(title, isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, MacFlowSpacing.space12)
        .frame(minHeight: 50)
    }

    private var statusColor: Color {
        switch controller.status {
        case .active: .green
        case .needsAccessibility: .orange
        case .disabled: MacFlowColor.textSecondary
        case .unavailable: .red
        }
    }

    private var permissionTitle: String {
        controller.isStableApplicationLocation
            ? "Accessibility permission required"
            : "Install this MacFlow build first"
    }

    private func revealCurrentApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct MouseFreeResponseChart: View {
    let speed: Double
    let smoothness: Double
    let acceleration: Double

    var body: some View {
        GeometryReader { proxy in
            let labelWidth: CGFloat = 44
            let chartRect = CGRect(
                x: labelWidth,
                y: 4,
                width: max(1, proxy.size.width - labelWidth),
                height: max(1, proxy.size.height - 24)
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for index in 0..<3 {
                        let y = chartRect.minY + chartRect.height * CGFloat(index) / 2
                        var guide = Path()
                        guide.move(to: CGPoint(x: chartRect.minX, y: y))
                        guide.addLine(to: CGPoint(x: chartRect.maxX, y: y))
                        context.stroke(
                            guide,
                            with: .color(MacFlowColor.borderSubtle),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                        )
                    }

                    let baseline = chartRect.maxY
                    let amplitude = chartRect.height * (0.46 + smoothness * 0.32)
                    let peakX = chartRect.minX + chartRect.width * (0.22 + acceleration * 0.10)
                    let tailX = chartRect.minX + chartRect.width * (0.72 + smoothness * 0.20)

                    var curve = Path()
                    curve.move(to: CGPoint(x: chartRect.minX, y: baseline))
                    curve.addCurve(
                        to: CGPoint(x: peakX, y: baseline - amplitude),
                        control1: CGPoint(x: chartRect.minX + chartRect.width * 0.08, y: baseline),
                        control2: CGPoint(x: peakX - chartRect.width * 0.09, y: baseline - amplitude)
                    )
                    curve.addCurve(
                        to: CGPoint(x: tailX, y: baseline - 3),
                        control1: CGPoint(x: peakX + chartRect.width * 0.18, y: baseline - amplitude * min(speed / 1.2, 1.35)),
                        control2: CGPoint(x: tailX - chartRect.width * 0.22, y: baseline - 5)
                    )
                    curve.addLine(to: CGPoint(x: chartRect.maxX, y: baseline))

                    var fill = curve
                    fill.addLine(to: CGPoint(x: chartRect.maxX, y: baseline))
                    fill.addLine(to: CGPoint(x: chartRect.minX, y: baseline))
                    fill.closeSubpath()
                    context.fill(
                        fill,
                        with: .linearGradient(
                            Gradient(colors: [MacFlowColor.mouseFree.opacity(0.12), .clear]),
                            startPoint: CGPoint(x: 0, y: chartRect.minY),
                            endPoint: CGPoint(x: 0, y: chartRect.maxY)
                        )
                    )
                    context.stroke(
                        curve,
                        with: .color(MacFlowColor.mouseFree),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }

                VStack(alignment: .leading) {
                    Text("FAST")
                    Spacer()
                    Text("MED")
                    Spacer()
                    Text("REST")
                }
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(MacFlowColor.textTertiary)
                .frame(width: labelWidth - 7, height: chartRect.height)

                HStack {
                    Text("INPUT")
                    Spacer()
                    Text("SETTLE")
                }
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(MacFlowColor.textTertiary)
                .padding(.leading, labelWidth)
                .offset(y: chartRect.maxY + 7)
            }
        }
    }
}
