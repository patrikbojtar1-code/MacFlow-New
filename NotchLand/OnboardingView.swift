//
//  OnboardingView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Content rendered inside the notch's "expanded-onboarding" branch on first
//  launch. The notch panel expands to fit this card; tapping GET STARTED
//  flips settings.hasCompletedOnboarding, which lets the regular branches
//  take over and the panel envelope shrink back.
//

import SwiftUI

enum OnboardingWizardStep: CaseIterable, Hashable {
    case welcome
    case showcase
    case profile
    case modules
    case permissions
    case ready
}

enum OnboardingMetrics {
    /// Inner body width × total height of the expanded notch during the
    /// welcome step. Width excludes the inverted-corner ears; height
    /// includes the full top-to-bottom envelope.
    static let notchSize = CGSize(width: 460, height: 278)

    /// Card size for the features/permissions wizard steps — bigger than
    /// the welcome step to fit icons, copy, and navigation chrome.
    static let expandedStepSize = CGSize(width: 540, height: 372)
    static let readyStepSize = CGSize(width: 480, height: 312)

    static func size(for step: OnboardingWizardStep) -> CGSize {
        switch step {
        case .welcome: notchSize
        case .ready: readyStepSize
        case .showcase, .profile, .modules, .permissions: expandedStepSize
        }
    }
}

enum OnboardingLockNotchMetrics {
    static let bodyWidth: CGFloat = 184
    static let height: CGFloat = 32
}

struct OnboardingLockNotchView: View {
    let isUnlocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didOpen = false

    var body: some View {
        Image(systemName: didOpen ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(didOpen ? Color(red: 0.23, green: 0.86, blue: 0.33) : .secondary)
            .contentTransition(.symbolEffect(.replace.downUp))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityLabel(didOpen ? "Unlocked" : "Locked")
            .onAppear {
                didOpen = isUnlocked
            }
            .onChange(of: isUnlocked) { _, unlocked in
                withAnimation(AppMotion.interaction(reduceMotion: reduceMotion)) {
                    didOpen = unlocked
                }
            }
    }
}

struct OnboardingView: View {
    @Binding var wizardStep: OnboardingWizardStep
    let onGetStarted: () -> Void
    let onWelcomeAnimationFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var widgetPreferences: WidgetPreferencesController
    @State private var hasAppeared = false
    @State private var movesForward = true
    @State private var didNotifyWelcome = false
    // Custom is truthful on first render and keeps replaying onboarding from
    // silently replacing an existing module setup.
    @State private var selectedProfile: OnboardingProfile = .custom

    init(
        wizardStep: Binding<OnboardingWizardStep>,
        onGetStarted: @escaping () -> Void,
        onWelcomeAnimationFinished: @escaping () -> Void = {}
    ) {
        self._wizardStep = wizardStep
        self.onGetStarted = onGetStarted
        self.onWelcomeAnimationFinished = onWelcomeAnimationFinished
    }

    var body: some View {
        VStack(spacing: MacFlowSpacing.space16) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(.horizontal, MacFlowSpacing.space24)
        .padding(.top, MacFlowSpacing.space32 + MacFlowSpacing.space8)
        .padding(.bottom, MacFlowSpacing.space16)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : -8)
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(AppMotion.insertion(reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
            if !didNotifyWelcome {
                didNotifyWelcome = true
                onWelcomeAnimationFinished()
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch wizardStep {
            case .welcome:
                OnboardingWelcomeStepView()
            case .showcase:
                OnboardingShowcaseStepView()
            case .profile:
                OnboardingProfileStepView(selection: $selectedProfile)
            case .modules:
                OnboardingModulesStepView()
            case .permissions:
                OnboardingPermissionsStepView()
            case .ready:
                OnboardingReadyStepView(onFinish: onGetStarted)
            }
        }
        .id(wizardStep)
        .transition(
            AppMotion.directionalTransition(
                reduceMotion: reduceMotion,
                forward: movesForward
            )
        )
    }

    @ViewBuilder
    private var footer: some View {
        if wizardStep != .ready {
            HStack(spacing: MacFlowSpacing.space12) {
                if wizardStep == .welcome {
                    Button("Skip", action: onGetStarted)
                        .buttonStyle(.borderless)
                } else {
                    Button("Back", systemImage: "chevron.left", action: goBack)
                        .buttonStyle(.bordered)
                }

                HStack(spacing: MacFlowSpacing.space4) {
                    ForEach(OnboardingWizardStep.allCases, id: \.self) { step in
                        Capsule(style: .continuous)
                            .fill(step == wizardStep ? Color.white : Color.white.opacity(0.22))
                            .frame(width: step == wizardStep ? 16 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(AppMotion.interaction(reduceMotion: reduceMotion), value: wizardStep)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Onboarding progress")
                .accessibilityValue(progressAccessibilityValue)

                Button("Continue", systemImage: "chevron.right", action: goNext)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
        }
    }

    private func goNext() {
        guard let index = OnboardingWizardStep.allCases.firstIndex(of: wizardStep),
              index < OnboardingWizardStep.allCases.index(before: OnboardingWizardStep.allCases.endIndex) else { return }
        if wizardStep == .profile {
            selectedProfile.apply(to: widgetPreferences)
        }
        movesForward = true
        NotchHaptics.perform(.navigation)
        withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
            wizardStep = OnboardingWizardStep.allCases[index + 1]
        }
    }

    private func goBack() {
        guard let index = OnboardingWizardStep.allCases.firstIndex(of: wizardStep), index > 0 else { return }
        movesForward = false
        NotchHaptics.perform(.navigation)
        withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
            wizardStep = OnboardingWizardStep.allCases[index - 1]
        }
    }

    private var progressAccessibilityValue: String {
        let current = OnboardingWizardStep.allCases.firstIndex(of: wizardStep) ?? 0
        return "Step \(current + 1) of \(OnboardingWizardStep.allCases.count)"
    }
}

private struct OnboardingNotchPreview: View {
    @State private var previewStep: OnboardingWizardStep = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let invertedRadius = FloatingNotchView.expandedInvertedRadius

    var body: some View {
        let bodySize = OnboardingMetrics.size(for: previewStep)
        let size = CGSize(
            width: bodySize.width + invertedRadius * 2,
            height: bodySize.height
        )
        let shape = NotchDropShape(
            invertedCornerRadius: invertedRadius,
            bottomCornerRadius: 20
        )

        ZStack(alignment: .top) {
            Color(red: 0.11, green: 0.11, blue: 0.12)
                .ignoresSafeArea()

            NotchPreviewContainer {
                ZStack(alignment: .bottom) {
                    shape.fill(Color.black)
                        .frame(width: size.width, height: size.height)

                    OnboardingView(
                        wizardStep: $previewStep,
                        onGetStarted: {}
                    )
                    .frame(width: bodySize.width, height: bodySize.height)
                }
                .clipShape(shape)
                .shadow(color: Color.black.opacity(0.42), radius: 18, x: 0, y: 8)
                .padding(.top, 18)
            }
            .animation(AppMotion.stateChange(reduceMotion: reduceMotion), value: previewStep)
        }
        .frame(width: 520, height: 320)
    }
}

private struct OnboardingContentPreview: View {
    @State private var wizardStep: OnboardingWizardStep = .welcome

    var body: some View {
        NotchPreviewContainer {
            OnboardingView(wizardStep: $wizardStep, onGetStarted: {})
                .frame(width: OnboardingMetrics.notchSize.width, height: OnboardingMetrics.notchSize.height)
                .background(Color.black)
        }
    }
}

private struct OnboardingLockPreview: View {
    let isUnlocked: Bool

    private let invertedRadius = FloatingNotchView.bareInvertedRadius
    private let bodySize = CGSize(
        width: OnboardingLockNotchMetrics.bodyWidth,
        height: OnboardingLockNotchMetrics.height
    )

    var body: some View {
        let size = CGSize(
            width: bodySize.width + invertedRadius * 2,
            height: bodySize.height
        )
        let shape = NotchDropShape(
            invertedCornerRadius: invertedRadius,
            bottomCornerRadius: bodySize.height / 2
        )

        ZStack(alignment: .top) {
            Color(red: 0.11, green: 0.11, blue: 0.12)
                .ignoresSafeArea()

            ZStack {
                shape.fill(Color.black)
                    .frame(width: size.width, height: size.height)

                OnboardingLockNotchView(isUnlocked: isUnlocked)
                    .frame(width: bodySize.width, height: bodySize.height)
            }
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.36), radius: 12, x: 0, y: 6)
            .padding(.top, 18)
        }
        .frame(width: 300, height: 92)
    }
}

#Preview("Onboarding Notch") {
    OnboardingNotchPreview()
}

#Preview("Onboarding Content") {
    OnboardingContentPreview()
}

#Preview("Onboarding Locked") {
    OnboardingLockPreview(isUnlocked: false)
}

#Preview("Onboarding Unlocked") {
    OnboardingLockPreview(isUnlocked: true)
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
