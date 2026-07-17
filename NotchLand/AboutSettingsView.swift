//
//  AboutSettingsView.swift
//  MacFlow
//

import SwiftUI

struct AboutSettingsView: View {
    var onIconClick: () -> Void = {}

    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var settings: NotchSettings

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(eyebrow: "MacFlow", title: "About")
            Divider().overlay(MacFlowColor.borderSubtle)

            ScrollView {
                VStack(spacing: MacFlowSpacing.space24) {
                    identity
                    information
                    Text(copyrightLine)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(MacFlowSpacing.space32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var identity: some View {
        VStack(spacing: MacFlowSpacing.space12) {
            MacFlowLogoTile(size: 64)
                .onTapGesture(perform: onIconClick)
                .accessibilityLabel("MacFlow application icon")
            VStack(spacing: MacFlowSpacing.space4) {
                Text("MacFlow").font(.title2.weight(.semibold))
                Text("Everything in rhythm.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Version \(version) (\(build))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MacFlowSpacing.space16)
    }

    private var information: some View {
        MacFlowSettingsGroup {
            MacFlowSettingsRow(
                icon: "square.grid.2x2",
                title: "Workspaces",
                subtitle: "Notch · MouseFree · Wallpapers"
            ) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            MacFlowInsetDivider()
            MacFlowSettingsRow(
                icon: "lock.shield",
                title: "Privacy",
                subtitle: "Preferences and workspace data stay on this Mac."
            ) {
                Text("Local").font(.caption).foregroundStyle(.secondary)
            }
            MacFlowInsetDivider()
            MacFlowSettingsRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Software Update",
                subtitle: settings.autoUpdateCheckEnabled ? "Automatic checks on" : "Automatic checks off"
            ) {
                Button("Check Now") { updater.checkForUpdates() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }

    private var copyrightLine: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Copyright © 2026 MacFlow. All rights reserved."
        }
        return value
    }
}
