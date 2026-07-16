//
//  MacFlowSidebarView.swift
//  MacFlow
//
//  Persistent product navigation shared by every module.
//

import SwiftUI

struct MacFlowSidebarView: View {
    @Binding var selection: MacFlowSection
    let showsDebug: Bool

    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var scenes: WallpaperSceneController
    @EnvironmentObject private var mouseFree: MouseFreeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Namespace private var selectionNamespace
    @State private var hoveredSection: MacFlowSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, MacFlowSpacing.space16)
                .padding(.top, MacFlowSpacing.space20)
                .padding(.bottom, MacFlowSpacing.space24)

            navigationGroup("Workspace", sections: [.home, .notch, .mouseFree, .wallpaperEngine])

            Spacer(minLength: MacFlowSpacing.space24)

            Divider()
                .overlay(MacFlowColor.borderSubtle)
                .padding(.horizontal, MacFlowSpacing.space16)
                .padding(.bottom, MacFlowSpacing.space12)

            navigationGroup("MacFlow", sections: utilitySections)
            runtimeSummary
                .padding(MacFlowSpacing.space12)
        }
        .background(reduceTransparency ? MacFlowColor.appBackground : MacFlowColor.sidebar)
    }

    private var brand: some View {
        HStack(spacing: MacFlowSpacing.space12) {
            MacFlowLogoTile(size: 40, showsShadow: false)
            VStack(alignment: .leading, spacing: MacFlowSpacing.space2) {
                Text("MacFlow")
                    .font(.system(size: 17, weight: .semibold))
                Text("Everything in rhythm")
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacFlowColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MacFlow, everything in rhythm")
    }

    private func navigationGroup(_ title: String, sections: [MacFlowSection]) -> some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MacFlowColor.textTertiary)
                .tracking(1.0)
                .padding(.horizontal, MacFlowSpacing.space20)
                .padding(.bottom, MacFlowSpacing.space6)

            ForEach(sections) { navigationButton($0) }
        }
        .padding(.horizontal, MacFlowSpacing.space10)
    }

    private func navigationButton(_ section: MacFlowSection) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section

        return Button {
            NotchHaptics.perform(.navigation)
            withAnimation(MacFlowMotion.selection(reduceMotion: reduceMotion)) {
                selection = section
            }
        } label: {
            HStack(spacing: MacFlowSpacing.space12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? MacFlowColor.accent : MacFlowColor.textSecondary)
                    .frame(width: 22)

                Text(section.title)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : MacFlowColor.textSecondary)

                Spacer(minLength: 0)

                if isSelected {
                    Capsule()
                        .fill(MacFlowColor.accent)
                        .frame(width: 3, height: 18)
                        .matchedGeometryEffect(id: "selection-indicator", in: selectionNamespace)
                }
            }
            .padding(.horizontal, MacFlowSpacing.space12)
            .frame(height: 42)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                        .fill(MacFlowColor.surface3)
                        .matchedGeometryEffect(id: "selection-background", in: selectionNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                        .fill(MacFlowColor.surface1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MacFlowInteractiveButtonStyle())
        .onHover { hovering in
            withAnimation(MacFlowMotion.hover(reduceMotion: reduceMotion)) {
                hoveredSection = hovering ? section : nil
            }
        }
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var utilitySections: [MacFlowSection] {
        var sections: [MacFlowSection] = [.preferences, .about]
        #if DEBUG
        if showsDebug { sections.append(.debug) }
        #endif
        return sections
    }

    private var runtimeSummary: some View {
        let activeCount = [
            settings.showNotch,
            mouseFree.status == .active,
            scenes.isRunning,
        ].filter { $0 }.count

        return VStack(alignment: .leading, spacing: MacFlowSpacing.space8) {
            HStack(spacing: MacFlowSpacing.space8) {
                Circle()
                    .fill(activeCount > 0 ? Color.green : MacFlowColor.textTertiary)
                    .frame(width: 7, height: 7)
                Text(activeCount > 0 ? "MacFlow is active" : "MacFlow is ready")
                    .font(.system(size: 11.5, weight: .medium))
            }
            Text("\(activeCount) of 3 modules running")
                .font(.system(size: 10.5))
                .foregroundStyle(MacFlowColor.textSecondary)
            RuntimeSparkline(activeCount: activeCount)
                .frame(height: 22)
                .accessibilityHidden(true)
        }
        .padding(MacFlowSpacing.space12)
        .background(
            reduceTransparency ? MacFlowColor.opaqueSurface1 : MacFlowColor.surface1,
            in: RoundedRectangle(cornerRadius: MacFlowRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.panel, style: .continuous)
                .stroke(
                    hasIncreasedContrast ? MacFlowColor.borderStrong : MacFlowColor.borderSubtle,
                    lineWidth: hasIncreasedContrast ? 1.25 : 1
                )
        }
        .accessibilityElement(children: .combine)
    }

    private var hasIncreasedContrast: Bool { colorSchemeContrast == .increased }
}

private struct RuntimeSparkline: View {
    let activeCount: Int

    var body: some View {
        Canvas { context, size in
            let strength = CGFloat(activeCount) / 3
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height * 0.68))
            path.addCurve(
                to: CGPoint(x: size.width * 0.55, y: size.height * (0.58 - strength * 0.12)),
                control1: CGPoint(x: size.width * 0.20, y: size.height * 0.70),
                control2: CGPoint(x: size.width * 0.36, y: size.height * 0.42)
            )
            path.addCurve(
                to: CGPoint(x: size.width, y: size.height * (0.28 + (1 - strength) * 0.28)),
                control1: CGPoint(x: size.width * 0.72, y: size.height * 0.76),
                control2: CGPoint(x: size.width * 0.88, y: size.height * 0.18)
            )
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [MacFlowColor.textTertiary, MacFlowColor.accent.opacity(0.80)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        }
    }
}
