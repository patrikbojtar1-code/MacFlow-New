//
//  FloatingNotchView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  The SwiftUI surface hosted inside the floating NSPanel. Renders the visible
//  notch (capsule when collapsed, rounded panel when expanded) inside a slightly
//  larger transparent canvas so the SwiftUI shadow has room to render.
//

import AppKit
import SwiftUI

/// A notch silhouette: rectangular top of width `topWidth`, widening with
/// concave shoulders into a body of width `rect.width`, with rounded bottom corners.
///
/// When `topWidth == rect.width` and `shoulderRadius == 0`, this degenerates to
/// a plain rectangle with rounded bottom corners (the non-notched fallback).
struct NotchShape: Shape {
    var topWidth: CGFloat
    var bottomCornerRadius: CGFloat
    var shoulderRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(topWidth, AnimatablePair(bottomCornerRadius, shoulderRadius))
        }
        set {
            topWidth = newValue.first
            bottomCornerRadius = newValue.second.first
            shoulderRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let bodyWidth = rect.width
        let height = rect.height
        let clampedTop = min(max(topWidth, 0), bodyWidth)
        let sideInset = (bodyWidth - clampedTop) / 2

        let maxShoulder = max(0, min(sideInset, height / 2))
        let shoulder = min(max(shoulderRadius, 0), maxShoulder)
        let hasShoulder = sideInset > 0 && shoulder > 0

        let maxBottom = max(0, min(bodyWidth / 2, height - shoulder))
        let bottom = min(max(bottomCornerRadius, 0), maxBottom)

        path.move(to: CGPoint(x: sideInset, y: 0))
        path.addLine(to: CGPoint(x: bodyWidth - sideInset, y: 0))

        // Right shoulder: smooth concave Bézier with control at the bounding corner.
        // Start tangent is horizontal (continues top edge); end tangent is vertical
        // (continues right wall).
        if hasShoulder {
            path.addQuadCurve(
                to: CGPoint(x: bodyWidth, y: shoulder),
                control: CGPoint(x: bodyWidth, y: 0)
            )
        }

        path.addLine(to: CGPoint(x: bodyWidth, y: height - bottom))

        if bottom > 0 {
            path.addArc(
                center: CGPoint(x: bodyWidth - bottom, y: height - bottom),
                radius: bottom,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: bottom, y: height))

        if bottom > 0 {
            path.addArc(
                center: CGPoint(x: bottom, y: height - bottom),
                radius: bottom,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: 0, y: shoulder))

        // Left shoulder: mirror of the right one.
        if hasShoulder {
            path.addQuadCurve(
                to: CGPoint(x: sideInset, y: 0),
                control: CGPoint(x: 0, y: 0)
            )
        }

        path.closeSubpath()
        return path
    }
}

struct FloatingNotchView: View {
    let displayID: UInt32?

    init(displayID: UInt32? = nil) {
        self.displayID = displayID
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hud: HUDController
    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var batteryAlerts: BatteryAlertController
    @EnvironmentObject var focusMode: FocusModeController
    @EnvironmentObject var screenLock: ScreenLockController
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var countdown: EventCountdownController
    @EnvironmentObject var airDrop: AirDropController
    @EnvironmentObject var fileShelf: FileShelfController
    @EnvironmentObject var liveActivities: LiveActivityController
    @EnvironmentObject var eventCenter: NotchEventCenter
    @EnvironmentObject var notchTimer: NotchTimerController
    @EnvironmentObject var calls: CallActivityController
    @EnvironmentObject var widgetPreferences: WidgetPreferencesController
    @EnvironmentObject var wallet: WalletContributionController
    @EnvironmentObject var scenes: WallpaperSceneController

    /// Used to morph shared elements (artwork, EQ bars) between the collapsed
    /// and expanded music states. Without this, SwiftUI cross-fades the small
    /// view out and the big one in, which reads as two layers stacking.
    /// `matchedGeometryEffect` makes them the *same* element at different sizes.
    @Namespace private var morph
    @State private var notchTransitionTask: Task<Void, Never>?
    @State private var renderedBranchKey: String?
    @State private var presentationMachine = NotchPresentationMachine()
    @State private var renderedBatteryPresentation: BatteryAlertController.Presentation?
    @State private var renderedFocusPresentation: FocusModeController.Presentation?
    @State private var renderedScreenLockPresentation: ScreenLockController.Presentation?
    @State private var renderedCallPresentation: CallPresentation?
    @State private var renderedWalletContribution: WalletContribution?
    @State private var isNotchPhaseAnimating = false
    @State private var notchBlendMotion: FeatureBlendMotion = .return
    @State private var suppressCollapsedMusicMarquee = false
    @State private var calendarCountdownShapeReveal: CGFloat = 1
    /// True for the lifetime of a transition whose source or destination is a
    /// calendar-countdown branch. Keeps `notchBody` on `calendarCountdownNotchBody`
    /// across the intermediate hardware-notch pivot, so SwiftUI preserves one
    /// view identity and the split shape morphs via `animatableData` instead of
    /// hard-cutting when the phase ends.
    @State private var calendarTransitionActive = false
    @State private var onboardingStage: OnboardingStage = .locked
    @State private var onboardingWizardStep: OnboardingWizardStep = .welcome
    @State private var borderReveal: CGFloat = 0
    /// First-launch choreography: notch starts collapsed, then drives the same
    /// expanded state used by normal interactions so onboarding grows out of
    /// the collapsed notch instead of appearing at full size.
    @State private var didRevealOnboarding = false
    @StateObject private var zoneController = NotchZoneController()
    private static let onboardingRevealDelay: Duration = .seconds(1)

    var body: some View {
        let displayKey = visualBranchKey
        let size = currentVisibleSize(for: displayKey)

        ZStack(alignment: .top) {
            notchBody(size: size, branchKey: displayKey)
                .frame(width: size.width, height: size.height, alignment: .top)
        }
        .environment(\.effectiveNotchSize, effectiveCompactNotchSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            NotchMotionGraph.animation(for: .selection, reduceMotion: reduceMotion),
            value: effectiveCompactNotchSize
        )
        .motionDebugProbe("Notch Shell")
        .onAppear {
            renderedBranchKey = branchKey
            presentationMachine.synchronize(to: branchKey)
            renderedBatteryPresentation = batteryAlerts.currentPresentation
            renderedFocusPresentation = focusMode.currentPresentation
            renderedScreenLockPresentation = screenLock.currentPresentation
            renderedCallPresentation = calls.current
            renderedWalletContribution = wallet.currentContribution
            playBorderEntrance()
            resetOnboardingStateIfNeeded()
        }
        .task(id: settings.hasCompletedOnboarding) {
            // First launch starts as a locked hardware-style notch, springs the
            // glyph open, then expands through the Dynamic Island transition.
            guard !settings.hasCompletedOnboarding else { return }
            resetOnboardingStateIfNeeded()
            try? await Task.sleep(for: Self.onboardingRevealDelay)
            guard !Task.isCancelled, !settings.hasCompletedOnboarding else { return }
            withAnimation(NotchMotionGraph.animation(for: .success, reduceMotion: reduceMotion)) {
                onboardingStage = .unlocking
            }
            try? await Task.sleep(for: .milliseconds(720))
            guard !Task.isCancelled, !settings.hasCompletedOnboarding else { return }
            withAnimation(OnboardingNotchMotion.openAnimation) {
                onboardingStage = .welcome
                didRevealOnboarding = true
                appState.isExpanded = true
            }
        }
        .onChange(of: batteryAlerts.currentPresentation) { _, presentation in
            if let presentation {
                renderedBatteryPresentation = presentation
            }
        }
        .onChange(of: focusMode.currentPresentation) { _, presentation in
            if let presentation {
                renderedFocusPresentation = presentation
            }
        }
        .onChange(of: screenLock.currentPresentation) { _, presentation in
            if let presentation {
                renderedScreenLockPresentation = presentation
            }
        }
        .onChange(of: calls.current) { _, presentation in
            if let presentation {
                renderedCallPresentation = presentation
            }
        }
        .onChange(of: appState.requestedWidgetRawValue) { _, rawValue in
            guard let rawValue, let widget = NotchWidget(rawValue: rawValue) else { return }
            widgetPreferences.setMode(.pinned, for: widget)
            withAnimation(NotchMotionGraph.animation(for: .selection, reduceMotion: reduceMotion)) {
                widgetPreferences.select(widget)
                fileShelf.isPresented = widget == .files
            }
            countdown.clearDetail()
            appState.expand()
            appState.consumeRequestedWidget()
        }
        .onChange(of: wallet.currentContribution) { _, contribution in
            guard let contribution,
                  settings.hasCompletedOnboarding,
                  widgetPreferences.mode(for: .wallet) != .hidden else { return }
            renderedWalletContribution = contribution
            widgetPreferences.select(.wallet)
        }
        .onChange(of: branchKey) { oldBranch, newBranch in
            let transition = presentationMachine.transition(to: newBranch)
            recordBranchMotion(transition)
            handleBranchChange(from: oldBranch, to: newBranch)
            playBorderEntrance()
            updateNotchZones()
        }
        .onChange(of: isHoveringThisDisplay) { _, isHovering in
            MotionDebug.record(
                name: "notch.hover",
                surface: "Notch Shell",
                duration: NotchMotionGraph.measurement(for: .hover).duration,
                state: isHovering ? "outside → hovering" : "hovering → outside",
                reason: "Pointer crossed the canonical AppKit hit region."
            )
            if !isHovering {
                suppressCollapsedMusicMarquee = false
            }
            updateNotchZones()
        }
        .onChange(of: effectiveCompactNotchSize) { oldSize, newSize in
            MotionDebug.record(
                name: "notch.content-size",
                surface: "Notch Shell",
                duration: NotchMotionGraph.measurement(for: .selection).duration,
                state: "\(oldSize.rawValue) → \(newSize.rawValue)",
                reason: "User changed the shared notch density setting."
            )
        }
        .onChange(of: appState.isExpanded) { _, isExpanded in
            if !isExpanded {
                countdown.clearDetail()
            }
            updateNotchZones()
        }
        .onChange(of: settings.hasCompletedOnboarding) { _, completed in
            if !completed {
                resetOnboardingStateIfNeeded()
            }
        }
        .onDisappear {
            notchTransitionTask?.cancel()
            zoneController.hide()
        }
    }

    private func resetOnboardingStateIfNeeded() {
        guard !settings.hasCompletedOnboarding else { return }
        notchTransitionTask?.cancel()
        withTransaction(Transaction(animation: nil)) {
            renderedBranchKey = "onboarding-lock"
            renderedBatteryPresentation = nil
            renderedFocusPresentation = nil
            renderedScreenLockPresentation = nil
            renderedCallPresentation = nil
            onboardingStage = .locked
            onboardingWizardStep = .welcome
            appState.resetToCollapsed()
            didRevealOnboarding = false
            isNotchPhaseAnimating = false
            calendarTransitionActive = false
            calendarCountdownShapeReveal = 1
            suppressCollapsedMusicMarquee = false
        }
    }

    private func recordBranchMotion(_ transition: NotchPresentationTransition) {
        let oldBranch = transition.fromBranch ?? transition.toBranch
        let newBranch = transition.toBranch
        let role: NotchMotionRole
        if transition.kind == .interruption || transition.kind == .restoration {
            role = .interruption
        } else if isGrowingTransition(from: oldBranch, to: newBranch) {
            role = .containerExpand
        } else {
            role = .dismiss
        }
        MotionDebug.record(
            name: "notch.presentation",
            surface: "Notch Shell",
            duration: NotchMotionGraph.measurement(for: role).duration,
            state: "\(oldBranch) → \(newBranch)",
            reason: "\(transition.kind.rawValue.capitalized): \(motionReason(for: newBranch))"
        )
    }

    private func motionReason(for branch: String) -> String {
        switch branch {
        case "call": "Incoming or active call won presentation priority."
        case "scene-drop-target", "file-shelf-drop-target": "A supported drag entered the notch proximity zone."
        case "expanded-widget", "expanded-event-detail": "User requested a larger interactive presentation."
        case "collapsed-music", "collapsed-music-event": "Media became the highest-priority compact activity."
        case "wallet-contribution": "A wallet contribution event became visible."
        case "scene": "The active wallpaper scene became the compact activity."
        case "collapsed-bare": "The previous activity ended and the notch returned to idle."
        default: "The canonical presentation resolver selected a new highest-priority activity."
        }
    }

    /// Radius of the body's bottom-left/right corners.
    private func bottomCornerRadius(for key: String) -> CGFloat {
        if key == "expanded-onboarding" {
            return Self.collapsedCornerRadius
        }
        if key == "collapsed-music" || isCallBranch(key) || key == "activity" || key == "important-event" {
            return NotchLayoutMetrics.bottomRadius(for: effectiveCompactNotchSize)
        }
        return isExpandedBranch(key) ? CGFloat(settings.cornerRadius) : Self.collapsedCornerRadius
    }

    /// Radius of the inverted (concave) top-outer corners. `0` collapses into
    /// a plain rounded-bottom rectangle; non-zero produces the NotchDrop-style
    /// curves. The value animates on the expansion spring along with the
    /// rest of the path.
    private func invertedCornerRadius(for key: String) -> CGFloat {
        NotchLayoutCoordinator.invertedRadius(for: key, isHovering: isHoveringThisDisplay)
    }

    static let collapsedCornerRadius = NotchLayoutCoordinator.collapsedCornerRadius
    static let expandedInvertedRadius = NotchLayoutCoordinator.expandedInvertedRadius
    static let musicInvertedRadius = NotchLayoutCoordinator.musicInvertedRadius
    static let bareInvertedRadius = NotchLayoutCoordinator.bareInvertedRadius
    private static let hardwareNotchBranchKey = NotchLayoutCoordinator.hardwareNotchBranchKey

    @ViewBuilder
    private func notchBody(size: CGSize, branchKey key: String) -> some View {
        if usesCalendarCountdownBody(for: key) {
            calendarCountdownNotchBody(size: size, branchKey: key)
        } else {
            standardNotchBody(size: size, branchKey: key)
        }
    }

    /// Whether `key` should render with the split calendar-countdown body.
    /// Includes the intermediate hardware-notch pivot while a calendar
    /// transition is in flight, so the body builder (and therefore the view
    /// identity) stays stable and the shape morphs continuously rather than
    /// swapping bodies — the swap is what made the split pop in.
    private func usesCalendarCountdownBody(for key: String) -> Bool {
        isCalendarCountdownBranch(key)
            || (key == Self.hardwareNotchBranchKey && calendarTransitionActive)
    }

    private func standardNotchBody(size: CGSize, branchKey key: String) -> some View {
        let bottomR = bottomCornerRadius(for: key)
        let invertedR = invertedCornerRadius(for: key)
        let isExpanded = isExpandedBranch(key)
        // let showsSoftBorder = !settings.useBlurMaterial || isCalendarSurfaceBranch(key)
        // The shape's inverted ears occupy `invertedR` of width on each side.
        // Keep this identical to the original transition path: one full-size
        // clipped shape whose body width morphs with the visible size.
        let bodyWidth = max(size.width - invertedR * 2, 0)
        let shape = NotchDropShape(
            invertedCornerRadius: invertedR,
            bottomCornerRadius: bottomR
        )

        return ZStack(alignment: .bottom) {
            notchDropBackground(shape: shape, forceBlack: isCalendarSurfaceBranch(key))
                .frame(width: size.width, height: size.height)

            content
                .frame(width: bodyWidth, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay {
            if isMusicBranch(key), colorSchemeContrast == .increased {
                shape
                    .stroke(.white.opacity(0.28), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .shadow(
            color: Color.black.opacity(
                settings.shadowIntensity * (isMusicBranch(key) && isHoveringThisDisplay ? 1.12 : 1)
            ),
            radius: isExpanded ? 18 : (isMusicBranch(key) && isHoveringThisDisplay ? 13 : 10),
            x: 0,
            y: isExpanded ? 8 : (isMusicBranch(key) ? 6 : 4)
        )
        .contentShape(shape)
        // Blue border is not needed for this version.
        /*
        .overlay {
            if showsSoftBorder {
                softBlueBorder(
                    invertedCornerRadius: invertedR,
                    bottomCornerRadius: bottomR
                )
            }
        }
        */
        .overlay {
            ZStack {
                if shouldShowNotchZones(for: key) {
                    NotchZonesOverlay(
                        totalWidth: size.width,
                        hardwareWidth: CGFloat(settings.collapsedWidth)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                // Expanded content owns its own controls. Keep the interaction
                // surface only for collapsed click-to-open behavior.
                if !isExpandedBranch(key), !isCallBranch(key) {
                    NotchInteractionSurface(
                        onTap: { location in handleNotchTap(at: location, size: size) }
                    )
                    .clipShape(shape)
                }
            }
        }
        .animation(NotchMotion.hover, value: isHoveringThisDisplay)
        .animation(
            NotchMotionGraph.animation(for: .zoneReveal, reduceMotion: reduceMotion),
            value: zoneController.phase
        )
    }

    private func calendarCountdownNotchBody(size: CGSize, branchKey key: String) -> some View {
        let bottomR = bottomCornerRadius(for: key)
        let invertedR = invertedCornerRadius(for: key)
        let isExpanded = isExpandedBranch(key)
        let baseWidth = CGFloat(settings.collapsedWidth)
        let targetBodyWidth: CGFloat
        let leftAnchorWidth: CGFloat

        if key == Self.hardwareNotchBranchKey {
            targetBodyWidth = max(size.width - invertedR * 2, 0)
            leftAnchorWidth = targetBodyWidth
        } else if key == "collapsed-music-event" {
            targetBodyWidth = EventCountdownChipMetrics.musicComboBodyWidth(baseWidth: baseWidth)
            leftAnchorWidth = EventCountdownChipMetrics.musicComboLeftAnchorWidth
        } else {
            targetBodyWidth = EventCountdownChipMetrics.eventOnlyBodyWidth(baseWidth: baseWidth)
            leftAnchorWidth = EventCountdownChipMetrics.eventOnlyLeftAnchorWidth
        }

        let containerBodyWidth = max(size.width - invertedR * 2, 0)
        let reveal = min(max(calendarCountdownShapeReveal, 0), 1)
        let symmetricBodyWidth = containerBodyWidth / 2
        let targetLeftBodyWidth = leftAnchorWidth / 2
        let targetRightBodyWidth = max(targetLeftBodyWidth, targetBodyWidth - targetLeftBodyWidth)
        let leftBodyWidth = symmetricBodyWidth + (targetLeftBodyWidth - symmetricBodyWidth) * reveal
        let rightBodyWidth = symmetricBodyWidth + (targetRightBodyWidth - symmetricBodyWidth) * reveal
        let contentWidth = containerBodyWidth + (targetBodyWidth - containerBodyWidth) * reveal
        let contentOffset = ((targetRightBodyWidth - targetLeftBodyWidth) / 2) * reveal
        let shape = CalendarCountdownNotchShape(
            leftBodyWidth: leftBodyWidth,
            rightBodyWidth: rightBodyWidth,
            invertedCornerRadius: invertedR,
            bottomCornerRadius: bottomR
        )

        return ZStack(alignment: .bottom) {
            calendarCountdownBackground(shape: shape)
                .frame(width: size.width, height: size.height)

            content
                .frame(width: contentWidth, height: size.height)
                .offset(x: contentOffset)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .frame(maxWidth: .infinity, alignment: .center)
        .shadow(
            color: Color.black.opacity(settings.shadowIntensity),
            radius: isExpanded ? 18 : 10,
            x: 0,
            y: isExpanded ? 8 : 4
        )
        .contentShape(shape)
        .overlay {
            if !isExpandedBranch(key) {
                NotchInteractionSurface(
                    onTap: { location in handleNotchTap(at: location, size: size) }
                )
                .clipShape(shape)
            }
        }
        .animation(NotchMotion.hover, value: isHoveringThisDisplay)
    }

    /// Fills the single-path notch shape with the configured style — solid
    /// black or the layered material (vibrancy + black overlay).
    @ViewBuilder
    private func notchDropBackground(shape: NotchDropShape, forceBlack: Bool = false) -> some View {
        if settings.useBlurMaterial && !forceBlack {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.45))
            }
        } else {
            shape.fill(Color.black)
        }
    }

    @ViewBuilder
    private func calendarCountdownBackground(shape: CalendarCountdownNotchShape) -> some View {
        shape.fill(Color.black)
    }

    private func softBlueBorder(
        invertedCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat
    ) -> some View {
        NotchDropBorderShape(
            invertedCornerRadius: invertedCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
            .stroke(
                Color(red: 0.22, green: 0.58, blue: 1.0).opacity(0.32 * borderReveal),
                lineWidth: 0.75
            )
            .shadow(
                color: Color(red: 0.16, green: 0.48, blue: 1.0).opacity(0.22 * borderReveal),
                radius: 5,
                x: 0,
                y: 0
            )
            .allowsHitTesting(false)
    }

    private func playBorderEntrance() {
        guard !reduceMotion else {
            borderReveal = 1
            return
        }

        borderReveal = 0
        withAnimation(NotchMotionGraph.animation(for: .contentReturn, reduceMotion: reduceMotion)) {
            borderReveal = 1
        }
    }

    private func handleNotchTap(at location: CGPoint, size: CGSize) {
        let key = branchKey
        if isExpandedBranch(key) {
            return
        }

        if shouldShowNotchZones(for: key) {
            switch NotchZoneLayout.zone(
                at: location.x,
                totalWidth: size.width,
                hardwareWidth: CGFloat(settings.collapsedWidth)
            ) {
            case .timeline:
                openZone(.timeline)
                return
            case .shortcuts:
                openZone(.shortcuts)
                return
            case .center:
                break
            }
        }

        switch key {
        case "event-collapsed":
            openEventDetail()
        case "collapsed-music-event":
            if location.x >= size.width / 2 {
                openEventDetail()
            } else {
                openDefaultExpansion()
            }
        case "collapsed-music" where location.x >= size.width - 72:
            guard nowPlaying.track?.compactPresentation.canPlayPause == true else { return }
            NotchHaptics.perform(.navigation)
            nowPlaying.togglePlayPause()
        case "scene" where location.x >= size.width - 78:
            NotchHaptics.perform(.navigation)
            if scenes.activeScene?.kind == .video {
                scenes.togglePaused()
            } else {
                scenes.requestOpenLibrary()
            }
        case "scene":
            NotchHaptics.perform(.navigation)
            scenes.requestOpenLibrary()
        case "scene-drop-target":
            return
        case "expanded-event-detail":
            return
        case "collapsed-bare" where !fileShelf.items.isEmpty:
            fileShelf.isPresented = true
            openDefaultExpansion()
        default:
            guard settings.openOnClick else { return }
            toggleDefaultExpansion()
        }
    }

    private var zonesAreEligible: Bool {
        settings.hasCompletedOnboarding
            && !appState.isExpanded
            && branchKey == "collapsed-bare"
            && !fileShelf.isDropTargetVisible
    }

    private func shouldShowNotchZones(for key: String) -> Bool {
        key == "collapsed-bare" && zoneController.isVisible && zonesAreEligible
    }

    private func updateNotchZones() {
        zoneController.update(
            isHovering: isHoveringThisDisplay,
            isEligible: zonesAreEligible,
            reduceMotion: reduceMotion
        )
    }

    private func openZone(_ widget: NotchWidget) {
        NotchHaptics.perform(.navigation)
        widgetPreferences.setMode(.pinned, for: widget)
        widgetPreferences.select(widget)
        fileShelf.isPresented = false
        appState.expand()
    }

    private func dismissTransientBranch(_ key: String) {
        switch key {
        case "battery-low", "battery-charging":
            batteryAlerts.dismissCurrentPresentation()
        case "focus-mode":
            focusMode.dismissCurrentPresentation()
        case "hud":
            hud.dismissCurrent()
        default:
            break
        }
    }

    private func openEventDetail() {
        guard countdown.trackedEvent != nil else {
            openDefaultExpansion()
            return
        }

        countdown.showDetail()
        appState.expand()
    }

    private func openDefaultExpansion() {
        countdown.clearDetail()
        if nowPlaying.track != nil, !fileShelf.isPresented {
            widgetPreferences.select(.media)
        }
        appState.expand()
    }

    private func toggleDefaultExpansion() {
        countdown.clearDetail()
        if !appState.isExpanded, nowPlaying.track != nil, !fileShelf.isPresented {
            widgetPreferences.select(.media)
        }
        appState.toggle()
    }

    /// Branches are inside one `ZStack`, with a soft emergence transition for
    /// the non-shared chrome (titles, scrubber, controls). Shared elements use
    /// `matchedGeometryEffect` (via the `morph` namespace passed into the music
    /// views) so the artwork & EQ bars don't fade — they literally morph their
    /// frame from the collapsed size/position to the expanded one along with
    /// the rectangle's spring. That's what makes the small notch *grow* into
    /// the big one instead of looking like two stacked layers.
    ///
    /// Every feature branch uses the same blurred content blend. The outer
    /// notch body handles the hardware-notch bridge, so branch content should
    /// feel like it is emerging from that shape instead of sitting above it.
    private var content: some View {
        let displayKey = visualBranchKey

        // Bottom alignment matters for the HUD: `HUDBarView` is a fixed-height
        // (28 pt) view that should sit in the drawer at the *bottom* of the
        // grown notch. The music/expanded branches override this with their own
        // `alignment: .top`/`.topLeading` frames, so they're unaffected.
        return ZStack(alignment: .bottom) {
            branchView(for: displayKey)
                .id(displayKey)
                .transition(branchTransition(for: displayKey))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func branchTransition(for _: String) -> AnyTransition {
        if isOnboardingBranch(visualBranchKey) || isOnboardingBranch(branchKey) {
            return .opacity.animation(OnboardingHeightMotion.contentAnimation)
        }
        return .featureBlend(notchBlendMotion)
    }

    private func handleBranchChange(from oldBranch: String, to newBranch: String) {
        notchTransitionTask?.cancel()
        renderedBranchKey = renderedBranchKey ?? oldBranch
        calendarTransitionActive = isCalendarCountdownBranch(oldBranch)
            || isCalendarCountdownBranch(newBranch)

        guard shouldUseGlobalFeatureMotion(from: oldBranch, to: newBranch) else {
            notchBlendMotion = .return
            renderedBranchKey = newBranch
            resetNotchTransition()
            return
        }

        if isCompactAlertBranch(oldBranch) || isCompactAlertBranch(newBranch) {
            handleCompactAlertBranchChange(from: oldBranch, to: newBranch)
            return
        }

        if isOnboardingBranch(oldBranch) || isOnboardingBranch(newBranch) {
            startOnboardingFeatureMotion(from: oldBranch, to: newBranch)
            return
        }

        startGlobalFeatureMotion(from: oldBranch, to: newBranch)
    }

    private func startOnboardingHeightMotion(to newBranch: String) {
        notchBlendMotion = .open
        isNotchPhaseAnimating = false
        withAnimation(OnboardingHeightMotion.expandAnimation) {
            renderedBranchKey = newBranch
        }
    }

    private func startOnboardingFeatureMotion(from oldBranch: String, to newBranch: String) {
        if isGrowingTransition(from: oldBranch, to: newBranch) {
            notchBlendMotion = .open
            withAnimation(OnboardingNotchMotion.openCompressAnimation) {
                isNotchPhaseAnimating = true
                renderedBranchKey = Self.hardwareNotchBranchKey
            }

            notchTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: OnboardingNotchMotion.openCompressDelayNanoseconds)
                guard !Task.isCancelled else { return }
                withAnimation(OnboardingNotchMotion.openAnimation) {
                    renderedBranchKey = newBranch
                }
                try? await Task.sleep(nanoseconds: OnboardingNotchMotion.openSettleDelayNanoseconds)
                guard !Task.isCancelled else { return }
                finishNotchPhase(targetBranch: newBranch)
            }
            return
        }

        notchBlendMotion = .return
        withAnimation(OnboardingNotchMotion.collapseAnimation) {
            isNotchPhaseAnimating = true
            renderedBranchKey = Self.hardwareNotchBranchKey
        }

        notchTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: OnboardingNotchMotion.returnDelayNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(OnboardingNotchMotion.returnAnimation) {
                renderedBranchKey = newBranch
            }
            try? await Task.sleep(nanoseconds: OnboardingNotchMotion.returnSettleDelayNanoseconds)
            guard !Task.isCancelled else { return }
            finishNotchPhase(targetBranch: newBranch)
        }
    }

    private func startGlobalFeatureMotion(from oldBranch: String, to newBranch: String) {
        if isGrowingTransition(from: oldBranch, to: newBranch) {
            notchBlendMotion = .open
            withAnimation(NotchFeatureMotion.openCompressAnimation) {
                isNotchPhaseAnimating = true
                renderedBranchKey = Self.hardwareNotchBranchKey
            }

            notchTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: NotchFeatureMotion.openCompressDelayNanoseconds)
                guard !Task.isCancelled else { return }
                withAnimation(NotchFeatureMotion.openAnimation) {
                    renderedBranchKey = newBranch
                }
                try? await Task.sleep(nanoseconds: NotchFeatureMotion.openSettleDelayNanoseconds)
                guard !Task.isCancelled else { return }
                finishNotchPhase(targetBranch: newBranch)
            }
            return
        }

        notchBlendMotion = .return
        withAnimation(NotchFeatureMotion.collapseAnimation) {
            isNotchPhaseAnimating = true
            renderedBranchKey = Self.hardwareNotchBranchKey
        }

        notchTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: NotchFeatureMotion.returnDelayNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(NotchFeatureMotion.returnAnimation) {
                renderedBranchKey = newBranch
            }
            try? await Task.sleep(nanoseconds: NotchFeatureMotion.returnSettleDelayNanoseconds)
            guard !Task.isCancelled else { return }
            finishNotchPhase(targetBranch: newBranch)
        }
    }

    private func handleCompactAlertBranchChange(from oldBranch: String, to newBranch: String) {
        if isCompactAlertBranch(newBranch) {
            notchBlendMotion = .open
            withAnimation(BatteryNotchMotion.expandAnimation) {
                isNotchPhaseAnimating = true
                renderedBranchKey = newBranch
            }

            notchTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: BatteryNotchMotion.expandDelayNanoseconds)
                guard !Task.isCancelled else { return }
                finishNotchPhase(targetBranch: newBranch)
            }
            return
        }

        notchBlendMotion = .return
        withAnimation(BatteryNotchMotion.collapseAnimation) {
            isNotchPhaseAnimating = true
            renderedBranchKey = Self.hardwareNotchBranchKey
        }

        notchTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: BatteryNotchMotion.collapseDelayNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(NotchFeatureMotion.returnAnimation) {
                renderedBranchKey = newBranch
            }
            try? await Task.sleep(nanoseconds: NotchFeatureMotion.returnSettleDelayNanoseconds)
            guard !Task.isCancelled else { return }
            finishNotchPhase(targetBranch: newBranch)
        }
    }

    private func shouldUseGlobalFeatureMotion(from oldBranch: String, to newBranch: String) -> Bool {
        oldBranch != newBranch
            && oldBranch != Self.hardwareNotchBranchKey
            && newBranch != Self.hardwareNotchBranchKey
    }

    private func isGrowingTransition(from oldBranch: String, to newBranch: String) -> Bool {
        visualArea(for: newBranch) >= visualArea(for: oldBranch)
    }

    private func visualArea(for key: String) -> CGFloat {
        let size = currentVisibleSize(for: key)
        return size.width * size.height
    }

    private func resetNotchTransition() {
        isNotchPhaseAnimating = false
        suppressCollapsedMusicMarquee = false
        calendarTransitionActive = false
    }

    private func finishNotchPhase(targetBranch: String) {
        suppressCollapsedMusicMarquee = isCollapsedMusicMarqueeBranch(targetBranch) && isHoveringThisDisplay
        if !isBatteryAlertBranch(targetBranch), batteryAlerts.currentPresentation == nil {
            renderedBatteryPresentation = nil
        }
        if !isFocusModeBranch(targetBranch), focusMode.currentPresentation == nil {
            renderedFocusPresentation = nil
        }
        if !isScreenLockBranch(targetBranch), screenLock.currentPresentation == nil {
            renderedScreenLockPresentation = nil
        }
        if !isCallBranch(targetBranch), calls.current == nil {
            renderedCallPresentation = nil
        }
        if !isWalletContributionBranch(targetBranch), wallet.currentContribution == nil {
            renderedWalletContribution = nil
        }
        withTransaction(Transaction(animation: nil)) {
            calendarCountdownShapeReveal = 1
            isNotchPhaseAnimating = false
            calendarTransitionActive = false
        }
    }

    @ViewBuilder
    private func branchView(for key: String) -> some View {
        switch key {
        case "battery-low", "battery-charging":
            if let presentation = batteryAlerts.currentPresentation ?? renderedBatteryPresentation {
                BatteryAlertView(presentation: presentation)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "focus-mode":
            if let presentation = focusMode.currentPresentation ?? renderedFocusPresentation {
                FocusModeAlertView(presentation: presentation)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "screen-lock":
            if let presentation = screenLock.currentPresentation ?? renderedScreenLockPresentation {
                LockScreenAlertView(presentation: presentation)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "file-shelf-drop-target":
            FileShelfDropZoneView()
        case "scene-drop-target":
            WallpaperSceneDropZoneView()
        case "call":
            if let presentation = calls.current ?? renderedCallPresentation {
                CallOverlayView(presentation: presentation)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "important-event":
            if let event = countdown.importantReminderEvent {
                ImportantEventReminderView(event: event)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "wallet-contribution":
            if let contribution = wallet.currentContribution ?? renderedWalletContribution {
                WalletContributionChipView(contribution: contribution)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "expanded-widget":
            ExpandedNotchWidgetHost(
                selection: widgetSelectionBinding,
                track: nowPlaying.track,
                morphNamespace: morph
            )
        case "expanded-event-detail":
            if let event = countdown.trackedEvent {
                FocusedEventDetailView(event: event)
            } else {
                CalendarNotchView()
            }
        case "expanded-bare":
            CalendarNotchView()
        case "expanded-onboarding":
            OnboardingView(wizardStep: $onboardingWizardStep) {
                settings.hasCompletedOnboarding = true
                appState.collapse()
            } onWelcomeAnimationFinished: {
                guard onboardingStage == .welcome else { return }
                withAnimation(OnboardingHeightMotion.expandAnimation) {
                    onboardingStage = .button
                }
            }
        case "onboarding-lock":
            OnboardingLockNotchView(isUnlocked: onboardingStage == .unlocking)
        case "hud":
            if let kind = hud.current {
                HUDBarView(kind: kind)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "activity":
            if let activity = liveActivities.current {
                LiveActivityChipView(activity: activity)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "scene":
            if let scene = scenes.activeScene {
                ZStack {
                    WallpaperSceneCompactView(scene: scene, isHovering: isHoveringThisDisplay)
                        .id(scene.id)
                        .transition(.opacity)
                }
                .animation(AppMotion.stateChange(reduceMotion: reduceMotion), value: scene.id)
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case Self.hardwareNotchBranchKey:
            Color.clear
        case "collapsed-music":
            if let track = nowPlaying.track {
                NowPlayingCollapsedView(
                    track: track,
                    isHovering: isHoveringThisDisplay,
                    morphNamespace: morph
                )
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "event-collapsed":
            if let presentation = countdown.presentation,
               let event = countdown.trackedEvent {
                EventCountdownCollapsedView(
                    presentation: presentation,
                    event: event,
                    side: .left
                )
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case "collapsed-music-event":
            if let track = nowPlaying.track,
               let presentation = countdown.presentation,
               let event = countdown.trackedEvent {
                CollapsedMusicEventView(
                    track: track,
                    presentation: presentation,
                    event: event,
                    isHovering: shouldShowCollapsedMusicMarquee(for: key),
                    morphNamespace: morph
                )
            } else if let track = nowPlaying.track {
                NowPlayingCollapsedView(
                    track: track,
                    isHovering: isHoveringThisDisplay,
                    morphNamespace: morph
                )
            } else {
                CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        default:
            CollapsedNotchContent(isHovering: isHoveringThisDisplay)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
    }

    /// A stable identifier for "which content is showing right now."
    /// Hover doesn't change the branch — only state transitions do — so the
    /// marquee fading in/out under music is handled inside the branch itself.
    private var branchKey: String {
        NotchPresentationResolver.branchKey(for: presentationResolutionInput)
    }

    private var presentationResolutionInput: NotchPresentationResolutionInput {
        NotchPresentationResolutionInput(
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            didRevealOnboarding: didRevealOnboarding,
            isExpanded: appState.isExpanded,
            screenLockBranchKey: screenLock.currentPresentation?.branchKey,
            eventRoute: eventPresentationRoute,
            hasCall: calls.current != nil,
            isSceneDropTargetVisible: scenes.isDropTargetVisible,
            isFileDropTargetVisible: fileShelf.isDropTargetVisible,
            batteryBranchKey: batteryAlerts.currentPresentation?.branchKey,
            focusBranchKey: focusMode.currentPresentation?.branchKey,
            hasWalletContribution: wallet.currentContribution != nil,
            hasImportantEvent: countdown.importantReminderEvent != nil,
            isEventDetailPresented: countdown.isDetailPresented,
            hasTrackedEvent: countdown.trackedEvent != nil,
            liveActivityBranchKey: liveActivities.current?.branchKey,
            hasHUD: hud.current != nil,
            hasEvent: countdown.presentation != nil,
            hasMedia: nowPlaying.track != nil,
            hasScene: scenes.activeScene != nil
        )
    }

    private var eventPresentationRoute: NotchEventPresentationRoute? {
        NotchEventPresentationPolicy.route(
            for: eventCenter.current,
            isExpanded: appState.isExpanded,
            isWalletVisible: widgetPreferences.mode(for: .wallet) != .hidden
        )
    }

    private var visualBranchKey: String {
        renderedBranchKey ?? branchKey
    }

    private func isExpandedBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isExpandedBranch(key)
    }

    private func isOnboardingBranch(_ key: String) -> Bool {
        key == "expanded-onboarding" || key == "onboarding-lock"
    }

    private func isMusicBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isMusicBranch(key)
    }

    private func isBatteryAlertBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isBatteryBranch(key)
    }

    private func isFocusModeBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isFocusBranch(key)
    }

    private func isScreenLockBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isScreenLockBranch(key)
    }

    private func isCallBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isCallBranch(key)
    }

    private func isWalletContributionBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isWalletBranch(key)
    }

    private func isCalendarCountdownBranch(_ key: String) -> Bool {
        key == "event-collapsed" || key == "collapsed-music-event"
    }

    private func isCalendarSurfaceBranch(_ key: String) -> Bool {
        isCalendarCountdownBranch(key)
            || key == "expanded-event-detail"
            || (key == "expanded-widget" && effectiveWidgetSelection == .calendar)
    }

    private func isFileShelfDropBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isFileDropBranch(key)
    }

    private func isSceneDropBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isSceneDropBranch(key)
    }

    private func isCompactAlertBranch(_ key: String) -> Bool {
        NotchPresentationResolver.isCompactAlertBranch(key)
    }

    private func isCollapsedMusicMarqueeBranch(_ key: String) -> Bool {
        key == "collapsed-music" || key == "collapsed-music-event"
    }

    private func shouldShowCollapsedMusicMarquee(for key: String) -> Bool {
        isCollapsedMusicMarqueeBranch(key)
            && branchKey == key
            && isHoveringThisDisplay
            && !isNotchPhaseAnimating
            && !suppressCollapsedMusicMarquee
    }

    private func currentCornerRadius(size: CGSize) -> CGFloat {
        isExpandedBranch(visualBranchKey) ? settings.cornerRadius : size.height / 2
    }

    private var effectiveCompactNotchSize: NotchSize {
        settings.contentSize(for: displayID)
    }

    private func currentVisibleSize(for key: String) -> CGSize {
        let callPresentation = calls.current ?? renderedCallPresentation
        let callSize = callPresentation.map {
            CallOverlayMetrics.size(for: $0, notchSize: effectiveCompactNotchSize)
        } ?? (effectiveCompactNotchSize == .small
            ? CallOverlayMetrics.incomingSize
            : CallOverlayMetrics.mediumSize)
        let widgetSize = effectiveWidgetSelection == .media
            && nowPlaying.track?.videoPresentation == nil
            ? NotchWidgetMetrics.audioExpandedSize
            : NotchWidgetMetrics.expandedSize
        return NotchLayoutCoordinator.visibleSize(
            for: NotchContentLayoutRequest(
                branchKey: key,
                baseBodySize: CGSize(
                    width: CGFloat(settings.collapsedWidth),
                    height: CGFloat(settings.collapsedHeight)
                ),
                expandedFallbackBodySize: CGSize(
                    width: max(CGFloat(settings.expandedWidth), CalendarNotchMetrics.expandedSize.width),
                    height: CalendarNotchMetrics.expandedSize.height
                ),
                onboardingBodySize: OnboardingMetrics.size(for: onboardingWizardStep),
                expandedWidgetBodySize: widgetSize,
                batteryBodyWidth: (batteryAlerts.currentPresentation ?? renderedBatteryPresentation)
                    .map(BatteryAlertMetrics.width(for:)) ?? BatteryAlertMetrics.chargingWidth,
                callBodySize: callSize,
                mediaPreferredWidth: nowPlaying.track?.compactPresentation.preferredWidth
                    ?? NowPlayingMetrics.collapsedWidth,
                compactSize: effectiveCompactNotchSize,
                isHovering: isHoveringThisDisplay,
                showsCollapsedMusicMarquee: shouldShowCollapsedMusicMarquee(for: key)
            )
        )
    }

    private var effectiveWidgetSelection: NotchWidget {
        if fileShelf.isPresented { return .files }
        let stored = widgetPreferences.selectedWidget
        if stored == .media, nowPlaying.track == nil { return .calendar }
        return stored
    }

    private var isHoveringThisDisplay: Bool {
        guard appState.isHovering else { return false }
        guard let displayID else { return true }
        return appState.activeDisplayID == displayID
    }

    private var widgetSelectionBinding: Binding<NotchWidget> {
        Binding(
            get: { effectiveWidgetSelection },
            set: { selection in
                widgetPreferences.select(selection)
                fileShelf.isPresented = selection == .files
            }
        )
    }
}

private enum OnboardingStage {
    case locked
    case unlocking
    case welcome
    case button
}

private enum OnboardingHeightMotion {
    static let expandAnimation = NotchMotionGraph.animation(for: .containerExpand)
    static let contentAnimation = NotchMotionGraph.animation(for: .contentEnter)
}

private enum NotchFeatureMotion {
    static let openingScale = NotchMotion.contentOpeningScale
    static let openingBlurRadius = NotchMotion.contentOpeningBlurRadius
    static let containerBlurRadius = NotchMotion.containerBlurRadius
    static let contentBlurRadius = NotchMotion.contentBlurRadius
    static let collapseDuration = NotchMotionGraph.measurement(for: .dismiss).duration
    static let openCompressDuration = NotchMotionGraph.compressDuration
    static let returnDelay: TimeInterval = collapseDuration
    static let openCompressDelay: TimeInterval = openCompressDuration
    static let openSettleDelay = NotchMotionGraph.openSettleDuration
    static let returnSettleDelay = NotchMotionGraph.returnSettleDuration
    static let returnDelayNanoseconds = UInt64(returnDelay * 1_000_000_000)
    static let openCompressDelayNanoseconds = UInt64(openCompressDelay * 1_000_000_000)
    static let openSettleDelayNanoseconds = UInt64(openSettleDelay * 1_000_000_000)
    static let returnSettleDelayNanoseconds = UInt64(returnSettleDelay * 1_000_000_000)
    static let openKickDelayNanoseconds = UInt64(NotchMotionGraph.handoffDelay * 1_000_000_000)

    static let collapseAnimation = NotchMotionGraph.animation(for: .dismiss)
    static let openCompressAnimation = NotchMotionGraph.compressionAnimation()
    static let openAnimation = NotchMotion.contentOpen
    static let returnAnimation = NotchMotion.contentReturn
}

private enum OnboardingNotchMotion {
    static let openingScale = NotchMotionGraph.contentScaleFrom
    static let openingBlurRadius = NotchMotionGraph.contentBlurRadius
    static let collapseDuration = NotchMotionGraph.measurement(for: .dismiss).duration
    static let openCompressDuration = NotchMotionGraph.compressDuration
    static let returnDelay: TimeInterval = collapseDuration
    static let openSettleDelay = NotchMotionGraph.openSettleDuration
    static let returnSettleDelay = NotchMotionGraph.returnSettleDuration
    static let openCompressDelayNanoseconds = UInt64(openCompressDuration * 1_000_000_000)
    static let returnDelayNanoseconds = UInt64(returnDelay * 1_000_000_000)
    static let openSettleDelayNanoseconds = UInt64(openSettleDelay * 1_000_000_000)
    static let returnSettleDelayNanoseconds = UInt64(returnSettleDelay * 1_000_000_000)
    static let openKickDelayNanoseconds = UInt64(NotchMotionGraph.handoffDelay * 1_000_000_000)

    static let collapseAnimation = NotchMotionGraph.animation(for: .dismiss)
    static let openCompressAnimation = NotchMotionGraph.compressionAnimation()
    static let openAnimation = NotchMotionGraph.animation(for: .containerExpand)
    static let returnAnimation = NotchMotionGraph.animation(for: .contentReturn)
}

private enum BatteryNotchMotion {
    static let expandDelayNanoseconds = UInt64(
        BatteryPresentationTiming.expandDuration * 1_000_000_000
    )
    static let collapseDelayNanoseconds = UInt64(
        BatteryPresentationTiming.collapseDuration * 1_000_000_000
    )

    static let expandAnimation = NotchMotionGraph.animation(for: .interruption)
    static let collapseAnimation = NotchMotionGraph.animation(for: .dismiss)
}

private struct FeatureContentBlendTransitionModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let hiddenProgress = 1 - progress

        content
            .scaleEffect(
                NotchMotionGraph.contentScaleFrom
                    + progress * (1 - NotchMotionGraph.contentScaleFrom),
                anchor: .top
            )
            .blur(radius: hiddenProgress * NotchFeatureMotion.contentBlurRadius)
            .opacity(Double(progress))
            .offset(y: hiddenProgress * NotchMotionGraph.contentOffsetFrom)
            .compositingGroup()
    }
}

private enum FeatureBlendMotion {
    case open
    case `return`
}

private extension AnyTransition {
    static func featureBlend(_ motion: FeatureBlendMotion) -> AnyTransition {
        switch motion {
        case .open:
            return .asymmetric(
                insertion: .featureContentBlend.animation(NotchFeatureMotion.openAnimation),
                removal: .featureContentBlend.animation(NotchFeatureMotion.openCompressAnimation)
            )
        case .return:
            return .asymmetric(
                insertion: .featureContentBlend.animation(NotchFeatureMotion.returnAnimation),
                removal: .featureContentBlend.animation(NotchFeatureMotion.collapseAnimation)
            )
        }
    }

    private static var featureContentBlend: AnyTransition {
        .modifier(
            active: FeatureContentBlendTransitionModifier(progress: 0),
            identity: FeatureContentBlendTransitionModifier(progress: 1)
        )
    }
}

// MARK: - NotchDrop-style notch shape (single Path)

/// A single `Shape` for the entire NotchDrop-style outline: rounded bottom
/// corners + flat top edge + concave (inverted) curves at the top-outer
/// corners. Renders in one pass with no compositing groups, no overlays, no
/// destination-out blend modes — that's what eliminates the "ears attach a
/// frame later" glitch the layered mask exhibited. `animatableData`
/// interpolates both radii together so every transition is one continuous
/// path tween.
struct NotchDropShape: Shape {
    /// Radius of the inverted top-outer corners (the "ears"). When `0`, the
    /// shape degenerates to a plain rounded-bottom rectangle (collapsed
    /// capsule look). When `> 0`, the body's top edge is shorter than its
    /// bottom edge by `2 * invertedCornerRadius`, with a concave quarter-arc
    /// at each top corner.
    var invertedCornerRadius: CGFloat
    /// Radius of the body's bottom-left and bottom-right corners.
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(invertedCornerRadius, bottomCornerRadius) }
        set {
            invertedCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }

        let ir = max(0, min(invertedCornerRadius, min(w / 2, h)))
        let br = max(0, min(bottomCornerRadius, min((w - ir * 2) / 2, h - ir)))

        // Outline traced clockwise on screen, starting at the top-left
        // (top-outer corner of the left ear).
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))

        // Right inverted (concave) top-outer corner: arc from (w, 0) curving
        // inward to (w - ir, ir). Arc center is at (w, ir) so the curve
        // bulges *into* the body's interior — a concave bite from outside.
        if ir > 0 {
            path.addArc(
                center: CGPoint(x: w, y: ir),
                radius: ir,
                startAngle: .degrees(270),  // direction: up
                endAngle: .degrees(180),    // direction: left
                clockwise: true             // math CW = short way
            )
        }

        // Body's right edge.
        path.addLine(to: CGPoint(x: w - ir, y: h - br))

        // Bottom-right rounded corner.
        if br > 0 {
            path.addArc(
                center: CGPoint(x: w - ir - br, y: h - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        // Bottom edge.
        path.addLine(to: CGPoint(x: ir + br, y: h))

        // Bottom-left rounded corner.
        if br > 0 {
            path.addArc(
                center: CGPoint(x: ir + br, y: h - br),
                radius: br,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        // Body's left edge.
        path.addLine(to: CGPoint(x: ir, y: ir))

        // Left inverted (concave) top-outer corner: mirror of the right.
        if ir > 0 {
            path.addArc(
                center: CGPoint(x: 0, y: ir),
                radius: ir,
                startAngle: .degrees(0),    // direction: right
                endAngle: .degrees(270),    // direction: up (= -90°)
                clockwise: true
            )
        }

        path.closeSubpath()
        return path
    }
}

private struct NotchDropBorderShape: Shape {
    var invertedCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(invertedCornerRadius, bottomCornerRadius) }
        set {
            invertedCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }

        let ir = max(0, min(invertedCornerRadius, min(w / 2, h)))
        let br = max(0, min(bottomCornerRadius, min((w - ir * 2) / 2, h - ir)))

        path.move(to: CGPoint(x: w, y: 0))

        if ir > 0 {
            path.addArc(
                center: CGPoint(x: w, y: ir),
                radius: ir,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: w - ir, y: h - br))

        if br > 0 {
            path.addArc(
                center: CGPoint(x: w - ir - br, y: h - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: ir + br, y: h))

        if br > 0 {
            path.addArc(
                center: CGPoint(x: ir + br, y: h - br),
                radius: br,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: ir, y: ir))

        if ir > 0 {
            path.addArc(
                center: CGPoint(x: 0, y: ir),
                radius: ir,
                startAngle: .degrees(0),
                endAngle: .degrees(270),
                clockwise: true
            )
        }

        return path
    }
}

struct CalendarCountdownNotchShape: Shape {
    var leftBodyWidth: CGFloat
    var rightBodyWidth: CGFloat
    var invertedCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(
                leftBodyWidth,
                AnimatablePair(
                    rightBodyWidth,
                    AnimatablePair(invertedCornerRadius, bottomCornerRadius)
                )
            )
        }
        set {
            leftBodyWidth = newValue.first
            rightBodyWidth = newValue.second.first
            invertedCornerRadius = newValue.second.second.first
            bottomCornerRadius = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }

        let leftBody = max(0, leftBodyWidth)
        let rightBody = max(0, rightBodyWidth)
        let ir = max(0, min(invertedCornerRadius, min(w / 2, h)))
        let bodyWidth = max(0, leftBody + rightBody)
        let br = max(0, min(bottomCornerRadius, min(bodyWidth / 2, h - ir)))

        let centerX = w / 2
        let x0 = max(0, centerX - leftBody - ir)
        let x1 = min(w, centerX + rightBody + ir)
        guard x1 > x0 else { return path }

        path.move(to: CGPoint(x: x0, y: 0))
        path.addLine(to: CGPoint(x: x1, y: 0))

        if ir > 0 {
            path.addArc(
                center: CGPoint(x: x1, y: ir),
                radius: ir,
                startAngle: .degrees(270),
                endAngle: .degrees(180),
                clockwise: true
            )
        }

        path.addLine(to: CGPoint(x: x1 - ir, y: h - br))

        if br > 0 {
            path.addArc(
                center: CGPoint(x: x1 - ir - br, y: h - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: x0 + ir + br, y: h))

        if br > 0 {
            path.addArc(
                center: CGPoint(x: x0 + ir + br, y: h - br),
                radius: br,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: x0 + ir, y: ir))

        if ir > 0 {
            path.addArc(
                center: CGPoint(x: x0, y: ir),
                radius: ir,
                startAngle: .degrees(0),
                endAngle: .degrees(270),
                clockwise: true
            )
        }

        path.closeSubpath()
        return path
    }
}

private struct CollapsedNotchContent: View {
    let isHovering: Bool

    var body: some View {
        HStack(spacing: 8) {
//            Text("NotchLand")
//                .font(.system(size: 12, weight: .semibold, design: .rounded))
//                .foregroundStyle(Color.white.opacity(isHovering ? 1.0 : 0.85))
        }
    }
}

private struct NotchZonesOverlay: View {
    let totalWidth: CGFloat
    let hardwareWidth: CGFloat

    var body: some View {
        let sideWidth = NotchZoneLayout.sideWidth(
            totalWidth: totalWidth,
            hardwareWidth: hardwareWidth
        )

        HStack(spacing: 0) {
            zone(symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90", title: "Timeline")
                .frame(width: sideWidth)

            Color.clear
                .frame(width: min(hardwareWidth, totalWidth))

            zone(symbol: "square.stack.3d.up.fill", title: "Shortcuts")
                .frame(width: sideWidth)
        }
        .frame(width: totalWidth)
        .padding(.bottom, 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func zone(symbol: String, title: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.68))
            .frame(width: 29, height: 24)
            .background(.white.opacity(0.075), in: Capsule(style: .continuous))
            .help(title)
    }
}

private struct NotchInteractionSurface: NSViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onTap: onTap)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onTap = onTap
    }

    final class TrackingView: NSView {
        var onTap: (CGPoint) -> Void

        private var mouseDownLocation: CGPoint?

        override var isFlipped: Bool { true }

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) not used")
        }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.ignoresMouseEvents = false
            mouseDownLocation = convert(event.locationInWindow, from: nil)
        }

        override func mouseUp(with event: NSEvent) {
            guard let start = mouseDownLocation else { return }
            let current = convert(event.locationInWindow, from: nil)
            let delta = CGPoint(
                x: current.x - start.x,
                y: current.y - start.y
            )

            if hypot(delta.x, delta.y) < 8 {
                onTap(current)
            }

            mouseDownLocation = nil
        }
    }
}

struct FloatingNotchViewPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            NotchShape(topWidth: 189, bottomCornerRadius: 10, shoulderRadius: 0)
                .fill(Color.black)
                .frame(width: 189, height: 32)
                .padding()
                .background(Color.gray.opacity(0.3))
                .previewDisplayName("NotchShape - collapsed")

            NotchShape(topWidth: 189, bottomCornerRadius: 18, shoulderRadius: 18)
                .fill(Color.black)
                .frame(width: 520, height: 140)
                .padding()
                .background(Color.gray.opacity(0.3))
                .previewDisplayName("NotchShape - expanded")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
