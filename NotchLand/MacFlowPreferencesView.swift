//
//  MacFlowPreferencesView.swift
//  MacFlow
//
//  Compatibility presentation until the dedicated Phase 5 preferences layout.
//

import SwiftUI

struct MacFlowPreferencesView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case general
        case appearance

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(
                eyebrow: "Application",
                title: "Preferences",
                subtitle: "Shared defaults for MacFlow."
            ) {
                Picker("Preferences section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            Divider().overlay(MacFlowColor.borderSubtle)

            if tab == .general {
                GeneralSettingsView()
            } else {
                AppearanceSettingsView()
            }
        }
    }
}
