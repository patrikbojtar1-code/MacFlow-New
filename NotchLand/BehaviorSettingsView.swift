//
//  BehaviorSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import AppKit
import SwiftUI

struct BehaviorSettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var hud: HUDController
    @EnvironmentObject var clipboard: ClipboardController
    @EnvironmentObject var calls: CallActivityController
    @EnvironmentObject var systemCalls: SystemCallActivitySource
    @EnvironmentObject var biometrics: BiometricAuthenticationController
    @EnvironmentObject var faceUnlock: FaceUnlockController
    @State private var showsFaceEnrollment = false

    var body: some View {
        Form {
            Section("Hover") {
                Toggle("Hover to Expand", isOn: $settings.hoverToExpand)
                Toggle("Click to Expand", isOn: $settings.openOnClick)
                Toggle("Auto-collapse on Mouse Exit", isOn: $settings.autoCollapse)
            }

            Section("Screen Lock") {
                Toggle("Lock & Unlock Animation", isOn: $settings.lockUnlockAnimationEnabled)
                Text("Shows a privacy-safe padlock surface during lock transitions and reliably restores the notch after sleep or wake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy Shield") {
                Toggle("Protect Private Widgets", isOn: biometricPrivacyBinding)
                    .disabled(!biometrics.isAvailable)

                HStack {
                    Label(biometrics.capability.title, systemImage: biometrics.capability.symbol)
                        .foregroundStyle(biometrics.isAvailable ? .primary : .secondary)
                    Spacer()
                    if settings.biometricPrivacyEnabled, biometrics.isAuthenticated {
                        Button("Lock Now") {
                            biometrics.lock()
                        }
                    }
                }

                Text("Wallet, Timeline, files, calendar, clipboard, notes, tasks and camera stay hidden until macOS authenticates you. NotchLand never receives biometric data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Face Unlock Beta") {
                Toggle("Unlock Private Widgets with Camera", isOn: faceUnlockBinding)
                    .disabled(!faceUnlock.isEnrolled)

                HStack {
                    Label(
                        faceUnlock.isEnrolled ? "Face profile enrolled" : "No face profile",
                        systemImage: faceUnlock.isEnrolled ? "faceid" : "person.crop.circle.badge.questionmark"
                    )
                    Spacer()
                    Button(faceUnlock.isEnrolled ? "Re-enroll" : "Enroll Face") {
                        showsFaceEnrollment = true
                        Task { await faceUnlock.beginEnrollment() }
                    }
                    if faceUnlock.isEnrolled {
                        Button("Delete", role: .destructive) {
                            settings.faceUnlockEnabled = false
                            faceUnlock.deleteEnrollment()
                        }
                    }
                }

                Text("Convenience-grade local protection for NotchLand only. Enrollment requires system authentication, frames are never stored, and three failed attempts force the system fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("HUD") {
                Toggle("Show HUD on Notch", isOn: showHUDOnNotchBinding)

                if settings.showHUDOnNotch, !hud.isAccessibilityTrusted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility permission is required for volume, brightness, and keyboard brightness keys.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Open Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Shows volume, brightness, keyboard brightness, and contrast changes inside the notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Clipboard") {
                Toggle("Keep Local Clipboard History", isOn: clipboardMonitoringBinding)
                Text("Stores up to 30 text snippets locally on this Mac. Clipboard content is never uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Call Appearance") {
                Toggle("Detect Calls & Messages", isOn: $settings.systemCallDetectionEnabled)

                if settings.systemCallDetectionEnabled, !systemCalls.isAccessibilityTrusted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility access is required to recognize call and Messages banners.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Allow Access") {
                            systemCalls.requestAccessibilityPermission()
                            openAccessibilitySettings()
                        }
                    }
                } else if settings.systemCallDetectionEnabled {
                    Label("Call and message detection is active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button {
                    if !settings.showNotch {
                        settings.showNotch = true
                    }
                    calls.showDesignPreview()
                } label: {
                    Label("Preview Incoming Call", systemImage: "phone.arrow.down.left")
                }
                Text("NotchLand recognizes FaceTime, iPhone call, iMessage and SMS Accessibility banners. Unrelated notification content is discarded and message text is kept only for the short on-screen animation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsFaceEnrollment) {
            FaceEnrollmentView()
                .environmentObject(faceUnlock)
                .environmentObject(settings)
        }
    }

    private var showHUDOnNotchBinding: Binding<Bool> {
        Binding {
            settings.showHUDOnNotch
        } set: { isEnabled in
            hud.setShowHUDOnNotch(isEnabled)
        }
    }

    private var clipboardMonitoringBinding: Binding<Bool> {
        Binding {
            clipboard.monitoringPreference
        } set: { isEnabled in
            clipboard.setMonitoringEnabled(isEnabled)
        }
    }

    private var biometricPrivacyBinding: Binding<Bool> {
        Binding {
            settings.biometricPrivacyEnabled
        } set: { enabled in
            settings.biometricPrivacyEnabled = enabled
            biometrics.lock()
        }
    }

    private var faceUnlockBinding: Binding<Bool> {
        Binding {
            settings.faceUnlockEnabled && faceUnlock.isEnrolled
        } set: { enabled in
            settings.faceUnlockEnabled = enabled && faceUnlock.isEnrolled
            if !enabled { faceUnlock.cancel() }
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
#Preview("Behavior Settings") {
    NotchPreviewContainer {
        BehaviorSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
