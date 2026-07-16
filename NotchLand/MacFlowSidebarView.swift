//
//  MacFlowSidebarView.swift
//  MacFlow
//
//  System sidebar navigation with native selection, focus, and keyboard behavior.
//

import SwiftUI

struct MacFlowSidebarView: View {
    @Binding var selection: MacFlowSection
    let showsDebug: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            brand
                .padding(.horizontal, MacFlowSpacing.space16)
                .padding(.vertical, MacFlowSpacing.space16)

            List(selection: selectionBinding) {
                Section("Workspace") {
                    rows([.home, .notch, .mouseFree, .wallpaperEngine])
                }

                Section("MacFlow") {
                    rows(utilitySections)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(MacFlowColor.sidebar)
    }

    private var selectionBinding: Binding<MacFlowSection?> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard let newSelection, newSelection != selection else { return }
                NotchHaptics.perform(.navigation)
                withAnimation(MacFlowMotion.selection(reduceMotion: reduceMotion)) {
                    selection = newSelection
                }
            }
        )
    }

    private var brand: some View {
        HStack(spacing: MacFlowSpacing.space8) {
            MacFlowLogoTile(size: 32, showsShadow: false)
            Text("MacFlow")
                .font(.headline)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MacFlow")
    }

    @ViewBuilder
    private func rows(_ sections: [MacFlowSection]) -> some View {
        ForEach(sections) { section in
            Label(section.title, systemImage: section.systemImage)
                .symbolRenderingMode(.hierarchical)
                .tag(section)
                .help(section.detail)
                .accessibilityHint(section.detail)
        }
    }

    private var utilitySections: [MacFlowSection] {
        var sections: [MacFlowSection] = [.preferences, .about]
        #if DEBUG
        if showsDebug { sections.append(.debug) }
        #endif
        return sections
    }
}
