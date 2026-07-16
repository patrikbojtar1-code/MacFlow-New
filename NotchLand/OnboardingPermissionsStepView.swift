//
//  OnboardingPermissionsStepView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Privacy-first permission step. Every permission stays optional.
//

import AppKit
import EventKit
import SwiftUI

struct OnboardingPermissionsStepView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var hud: HUDController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions, only when needed")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("MacFlow works without these. Enable only the experiences you want.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

            VStack(spacing: 10) {
                permissionRow(
                    symbol: "calendar",
                    title: "Calendar",
                    detail: "Show today's events and countdowns.",
                    isGranted: calendar.canReadEvents,
                    actionTitle: calendarActionTitle,
                    action: calendarAction
                )

                permissionRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    detail: "Replace the system volume/brightness HUD.",
                    isGranted: hud.isAccessibilityTrusted,
                    actionTitle: hud.hasRequestedAccessibilityThisRun ? "Open Settings" : "Enable",
                    action: {
                        if hud.hasRequestedAccessibilityThisRun {
                            openAccessibilitySettings()
                        } else {
                            hud.requestAccessibilityPermissionIfNeeded()
                        }
                    }
                )

                HStack(spacing: 10) {
                    Image(systemName: "touchid")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Touch ID Privacy Shield")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Requested only when you unlock a private widget.")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.56))
                    }
                    Spacer()
                    Text("ON DEMAND")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.44))
                }

                HStack(spacing: 10) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Camera stays off")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("Mirror asks for access only when you open it.")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Text("ON DEMAND")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                }
            }

            Label(
                "Permission status is checked live; already granted access is never requested again.",
                systemImage: "checkmark.shield.fill"
            )
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.46))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func permissionRow(
        symbol: String,
        title: String,
        detail: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isGranted ? Color(red: 0.23, green: 0.86, blue: 0.33) : .white.opacity(0.8))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 8)

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.23, green: 0.86, blue: 0.33))
            } else {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var calendarActionTitle: String {
        calendar.authorizationStatus == .denied || calendar.authorizationStatus == .restricted
            ? "Open Settings"
            : "Enable"
    }

    private func calendarAction() {
        switch calendar.authorizationStatus {
        case .denied, .restricted:
            openCalendarPrivacySettings()
        default:
            calendar.requestAccess()
        }
    }

    private func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
#Preview("Onboarding Permissions Step") {
    NotchPreviewContainer {
        OnboardingPermissionsStepView()
            .padding(20)
            .frame(
                width: OnboardingMetrics.expandedStepSize.width,
                height: OnboardingMetrics.expandedStepSize.height
            )
            .background(Color.black)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
