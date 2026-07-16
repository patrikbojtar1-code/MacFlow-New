//
//  AboutSettingsView.swift
//  MacFlow
//
//  Product identity, version, updates, and local-first principles.
//

import AppKit
import SwiftUI

struct AboutSettingsView: View {
    var onIconClick: () -> Void = {}

    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var settings: NotchSettings

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var copyrightLine: String {
        let value = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false
            ? trimmed!
            : "Copyright © 2026 MacFlow. All rights reserved."
    }

    var body: some View {
        VStack(spacing: 0) {
            MacFlowPageHeader(
                eyebrow: "Product",
                title: "About MacFlow",
                subtitle: "One native workspace for the Mac you use every day."
            )
            Divider().overlay(MacFlowColor.borderSubtle)

            ScrollView {
                HStack(alignment: .top, spacing: MacFlowSpacing.space20) {
                    identityPanel
                    informationColumn
                }
                .frame(maxWidth: 900)
                .padding(MacFlowSpacing.space32)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.never)
        }
    }

    private var identityPanel: some View {
        MacFlowPanel(.elevated) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space20) {
                MacFlowLogoTile(size: 92)
                    .onTapGesture(perform: onIconClick)
                    .accessibilityLabel("MacFlow application icon")

                VStack(alignment: .leading, spacing: MacFlowSpacing.space6) {
                    Text("MacFlow")
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.5)
                    Text("Everything in rhythm.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacFlowColor.textSecondary)
                    Text("Notch activities, precise scrolling and living wallpapers—coordinated from a single macOS app.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacFlowColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, MacFlowSpacing.space4)
                }

                HStack(spacing: MacFlowSpacing.space8) {
                    productChip("Notch", icon: "macbook", color: MacFlowColor.notch)
                    productChip("MouseFree", icon: "computermouse.fill", color: MacFlowColor.mouseFree)
                    productChip("Wallpapers", icon: "photo.fill", color: MacFlowColor.wallpaper)
                }
            }
            .padding(MacFlowSpacing.space24)
        }
        .frame(width: 360)
    }

    private var informationColumn: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space16) {
            MacFlowSettingsGroup {
                aboutRow("Version", value: version, icon: "shippingbox")
                MacFlowInsetDivider()
                aboutRow("Build", value: build, icon: "hammer")
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Software Update",
                    subtitle: settings.autoUpdateCheckEnabled ? "Automatic checks are enabled." : "Automatic checks are disabled."
                ) {
                    Button("Check Now") { updater.checkForUpdates() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!updater.canCheckForUpdates)
                }
            }

            MacFlowPanel(.grouped) {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                    Label("Local by design", systemImage: "lock.shield.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MacFlowColor.accent)
                    Text("MacFlow keeps module preferences and local workspace data on this Mac. System permissions remain under your control in macOS Settings.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacFlowColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MacFlowSpacing.space16)
            }

            VStack(alignment: .leading, spacing: MacFlowSpacing.space6) {
                Text(copyrightLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacFlowColor.textTertiary)
                Text("Built for macOS with SwiftUI, AppKit and original MacFlow visuals.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacFlowColor.textTertiary)
            }
            .padding(.horizontal, MacFlowSpacing.space4)
        }
        .frame(maxWidth: .infinity)
    }

    private func aboutRow(_ title: String, value: String, icon: String) -> some View {
        MacFlowSettingsRow(icon: icon, title: title) {
            Text(value)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(MacFlowColor.textSecondary)
        }
    }

    private func productChip(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, MacFlowSpacing.space8)
            .frame(height: 26)
            .background(color.opacity(0.09), in: Capsule())
            .overlay { Capsule().stroke(color.opacity(0.16), lineWidth: 1) }
    }
}
