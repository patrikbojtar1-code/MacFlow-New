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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var selectionNamespace
    @State private var hoveredSection: MacFlowSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, MacFlowSpacing.space12)
                .padding(.top, MacFlowSpacing.space16)
                .padding(.bottom, MacFlowSpacing.space20)

            navigationGroup("Workspace", sections: [.home, .notch, .mouseFree, .wallpaperEngine])

            Spacer(minLength: MacFlowSpacing.space24)

            Divider()
                .overlay(MacFlowColor.borderSubtle)
                .padding(.horizontal, MacFlowSpacing.space16)
                .padding(.bottom, MacFlowSpacing.space12)

            navigationGroup("MacFlow", sections: utilitySections)
                .padding(.bottom, MacFlowSpacing.space16)
        }
        .background(reduceTransparency ? MacFlowColor.appBackground : MacFlowColor.sidebar)
    }

    private var brand: some View {
        HStack(spacing: MacFlowSpacing.space10) {
            MacFlowLogoTile(size: 34, showsShadow: false)
            VStack(alignment: .leading, spacing: MacFlowSpacing.space2) {
                Text("MacFlow")
                    .font(.system(size: 15, weight: .semibold))
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
                .padding(.horizontal, MacFlowSpacing.space12)
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
            HStack(spacing: MacFlowSpacing.space10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? MacFlowColor.accent : MacFlowColor.textSecondary)
                    .frame(width: 22)

                Text(section.title)
                    .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : MacFlowColor.textSecondary)

                Spacer(minLength: 0)

                if isSelected {
                    Capsule()
                        .fill(MacFlowColor.accent)
                        .frame(width: 3, height: 18)
                        .matchedGeometryEffect(id: "selection-indicator", in: selectionNamespace)
                }
            }
            .padding(.horizontal, MacFlowSpacing.space10)
            .frame(height: 38)
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

}
