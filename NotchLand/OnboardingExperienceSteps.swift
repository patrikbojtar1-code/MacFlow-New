//
//  OnboardingExperienceSteps.swift
//  NotchLand
//
//  Interactive, sample-driven onboarding screens. These views deliberately
//  use local fixtures so first launch never depends on network or system data.
//

import Foundation
import SwiftUI

enum OnboardingProfile: String, CaseIterable, Identifiable {
    case productivity
    case creator
    case minimal
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .productivity: "Productivity"
        case .creator: "Creator"
        case .minimal: "Minimal"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .productivity: "Calendar, tasks, notes and focus."
        case .creator: "Wallet, media, files and actions."
        case .minimal: "Only essentials, context appears automatically."
        case .custom: "Keep the current setup and tune it yourself."
        }
    }

    var symbol: String {
        switch self {
        case .productivity: "checkmark.circle.fill"
        case .creator: "sparkles"
        case .minimal: "circle.lefthalf.filled"
        case .custom: "slider.horizontal.3"
        }
    }

    var accent: Color {
        switch self {
        case .productivity: .blue
        case .creator: .purple
        case .minimal: .white
        case .custom: .orange
        }
    }

    @MainActor
    func apply(to preferences: WidgetPreferencesController) {
        switch self {
        case .productivity:
            preferences.applyConfiguration(
                preferredOrder: [.calendar, .tasks, .notes, .timer, .files, .clipboard, .media, .actions, .wallet, .mirror],
                pinned: [.calendar, .tasks, .notes, .timer],
                automatic: [.files, .clipboard, .media, .wallet]
            )
        case .creator:
            preferences.applyConfiguration(
                preferredOrder: [.wallet, .media, .files, .actions, .calendar, .clipboard, .timer, .notes, .tasks, .mirror],
                pinned: [.wallet, .media, .files, .actions],
                automatic: [.calendar, .clipboard, .timer]
            )
        case .minimal:
            preferences.applyConfiguration(
                preferredOrder: [.media, .calendar, .files, .wallet, .timer, .clipboard, .actions, .notes, .tasks, .mirror],
                pinned: [.media, .calendar, .files],
                automatic: [.wallet, .timer, .clipboard]
            )
        case .custom:
            break
        }
    }
}

struct OnboardingWelcomeStepView: View {
    private var firstName: String {
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return fullName.split(separator: " ").first.map(String.init) ?? "there"
    }

    var body: some View {
        VStack(spacing: 9) {
            VStack(spacing: 2) {
                Text("Hello, \(firstName)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                Text("Meet the space around your notch.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(NotchTheme.secondaryText)
            }

            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Now Playing")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.black
                    .frame(width: 92)
                    .accessibilityHidden(true)

                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(0.78))
                            .frame(
                                width: 2,
                                height: CGFloat([11, 7, 14, 9, 12][index])
                            )
                    }
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.leading, 7)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(NotchTheme.subtleStroke, lineWidth: 1)
            }

            Text("Media, calls, devices and reminders stay outside the camera cutout.")
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OnboardingShowcaseStepView: View {
    private enum Demo: Int, CaseIterable, Identifiable {
        case media, files, wallet, call

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .media: "Now Playing"
            case .files: "File Shelf"
            case .wallet: "Wallet payments"
            case .call: "Incoming calls"
            }
        }
        var detail: String {
            switch self {
            case .media: "Control Apple Music, Spotify and Apple TV."
            case .files: "Drop, preview and share files without opening Finder."
            case .wallet: "See BTC, LTC, ETH and SOL contributions instantly."
            case .call: "A calm, glanceable call experience around the notch."
            }
        }
        var symbol: String {
            switch self {
            case .media: "music.note"
            case .files: "tray.full.fill"
            case .wallet: "wallet.bifold.fill"
            case .call: "phone.fill"
            }
        }
        var accent: Color {
            switch self {
            case .media: .pink
            case .files: .blue
            case .wallet: .orange
            case .call: .green
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Demo = .media

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("See it before you set it up")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("This is how live moments will appear in your notch.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }

            HStack(spacing: 16) {
                showcaseCanvas

                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: selection.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selection.accent)
                        .contentTransition(.symbolEffect(.replace))
                    Text(selection.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(selection.detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 7) {
                ForEach(Demo.allCases) { demo in
                    Button {
                        withAnimation(AppMotion.interaction(reduceMotion: reduceMotion)) {
                            selection = demo
                        }
                    } label: {
                        Image(systemName: demo.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selection == demo ? .black : .white.opacity(0.55))
                            .frame(width: 30, height: 24)
                            .background(
                                selection == demo ? demo.accent : Color.white.opacity(0.07),
                                in: Capsule(style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var showcaseCanvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [selection.accent.opacity(0.18), .white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            demoContent
                .id(selection)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .frame(width: 290, height: 164)
    }

    @ViewBuilder
    private var demoContent: some View {
        switch selection {
        case .media:
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 62, height: 62)
                    .overlay(Image(systemName: "music.note").font(.title2.bold()))
                VStack(alignment: .leading, spacing: 7) {
                    Text("Midnight Drive").font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("NotchLand Sessions").font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "pause.fill")
                        Image(systemName: "forward.fill")
                    }.font(.system(size: 11, weight: .semibold))
                }
            }
        case .files:
            HStack(spacing: 10) {
                ForEach(["photo.fill", "doc.fill", "archivebox.fill"], id: \.self) { symbol in
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 58, height: 66)
                        .overlay(Image(systemName: symbol).font(.title3).foregroundStyle(.blue))
                }
            }
        case .wallet:
            HStack(spacing: 13) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Payment received").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("+$15.00").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                    Label("Confirmed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.green)
                }
            }
        case .call:
            HStack(spacing: 14) {
                Circle().fill(.green.opacity(0.2)).frame(width: 54, height: 54)
                    .overlay(Image(systemName: "person.fill").font(.title2).foregroundStyle(.green))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Incoming call").font(.system(size: 9)).foregroundStyle(.secondary)
                    Text("Patrik").font(.system(size: 16, weight: .semibold, design: .rounded))
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 25, height: 25).overlay(Image(systemName: "phone.down.fill").font(.caption))
                        Circle().fill(.green).frame(width: 25, height: 25).overlay(Image(systemName: "phone.fill").font(.caption))
                    }
                }
            }
        }
    }
}

struct OnboardingProfileStepView: View {
    @Binding var selection: OnboardingProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Make it yours")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Choose a starting point. You can change every module later.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingProfile.allCases) { profile in
                    profileCard(profile)
                }
            }
        }
    }

    private func profileCard(_ profile: OnboardingProfile) -> some View {
        let isSelected = selection == profile
        return Button {
            withAnimation(AppMotion.interaction(reduceMotion: reduceMotion)) {
                selection = profile
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: profile.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(profile.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(profile.detail)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(2)
                }
                Spacer(minLength: 2)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(profile.accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                isSelected ? profile.accent.opacity(0.13) : Color.white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? profile.accent.opacity(0.38) : .white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(AppMotion.interaction(reduceMotion: reduceMotion), value: isSelected)
    }
}

struct OnboardingModulesStepView: View {
    @EnvironmentObject private var preferences: WidgetPreferencesController
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Build your top rail")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Click a module to cycle through Pinned, Automatic and Hidden.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(preferences.orderedWidgets) { widget in
                    moduleRow(widget)
                }
            }

            HStack(spacing: 14) {
                legend(.pinned)
                legend(.automatic)
                legend(.hidden)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func moduleRow(_ widget: NotchWidget) -> some View {
        let mode = preferences.mode(for: widget)
        return Button {
            preferences.setMode(nextMode(after: mode), for: widget)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: widget.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 17)
                Text(widget.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: mode.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color(for: mode))
                Text(mode.title)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))
                    .frame(width: 46, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(.white.opacity(mode == .hidden ? 0.025 : 0.055), in: RoundedRectangle(cornerRadius: 10))
            .opacity(mode == .hidden ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }

    private func legend(_ mode: WidgetVisibilityMode) -> some View {
        Label(mode.title, systemImage: mode.symbol)
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(color(for: mode))
    }

    private func nextMode(after mode: WidgetVisibilityMode) -> WidgetVisibilityMode {
        switch mode {
        case .pinned: .automatic
        case .automatic: .hidden
        case .hidden: .pinned
        }
    }

    private func color(for mode: WidgetVisibilityMode) -> Color {
        switch mode {
        case .pinned: .white
        case .automatic: .purple
        case .hidden: .gray
        }
    }
}

struct OnboardingReadyStepView: View {
    let onFinish: () -> Void
    @EnvironmentObject private var preferences: WidgetPreferencesController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.14))
                    .frame(width: 58, height: 58)
                Image(systemName: "checkmark")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.green)
            }
            .scaleEffect(didAppear ? 1 : 0.45)

            VStack(spacing: 4) {
                Text("Your notch is ready")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("Hover, click or use ⌘1…9 to move between your modules.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 5) {
                ForEach(Array(preferences.visibleWidgets.prefix(7))) { widget in
                    Image(systemName: widget.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 27, height: 24)
                        .background(.white.opacity(0.07), in: Capsule())
                }
            }

            Button("Start MacFlow", systemImage: "arrow.right", action: onFinish)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(AppMotion.emphasized(reduceMotion: reduceMotion)) {
                didAppear = true
            }
        }
    }
}
