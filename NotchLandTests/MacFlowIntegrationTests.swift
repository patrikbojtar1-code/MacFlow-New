//
//  MacFlowIntegrationTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

struct MacFlowIntegrationTests {
    private let balanced = MouseScrollConfiguration(
        speed: 1.15,
        smoothness: 0.55,
        acceleration: 0.35
    )

    @Test func compactShellFitsAThirteenInchMacBookWorkspace() {
        #expect(MacFlowMetrics.idealWindowWidth <= 1_040)
        #expect(MacFlowMetrics.idealWindowHeight <= 680)
        #expect(MacFlowMetrics.minimumWindowWidth <= 820)
        #expect(MacFlowMetrics.minimumWindowHeight <= 560)
        #expect(MacFlowMetrics.readableContentMaxWidth >= MacFlowMetrics.idealWindowWidth - MacFlowMetrics.sidebarWidth)
    }

    @Test func smallNotchDensityIsActuallyCompact() {
        #expect(NotchLayoutMetrics.bodySize(for: .small).width <= 460)
        #expect(NotchLayoutMetrics.bodySize(for: .small).height <= 54)
        #expect(NowPlayingMetrics.compactHeight(for: .small) <= 54)
        #expect(WallpaperSceneNotchMetrics.compactSize.width <= 460)
        #expect(WallpaperSceneNotchMetrics.compactSize.width < WallpaperSceneNotchMetrics.mediumSize.width)
    }

    @Test func wallpaperHoverOnlyAddsAPreviewEnvelope() {
        let base = WallpaperSceneNotchMetrics.size(for: .small)
        let hovered = WallpaperSceneNotchMetrics.size(for: .small, isHovering: true)
        #expect(hovered.width - base.width == NotchLayoutMetrics.hoverWidthExpansion)
        #expect(hovered.height - base.height == NotchLayoutMetrics.hoverHeightExpansion)
    }

    @Test func macFlowSpacingUsesTheDocumentedScale() {
        #expect([
            MacFlowSpacing.space4,
            MacFlowSpacing.space8,
            MacFlowSpacing.space12,
            MacFlowSpacing.space16,
            MacFlowSpacing.space24,
            MacFlowSpacing.space32,
            MacFlowSpacing.space48,
        ] == [4, 8, 12, 16, 24, 32, 48])
    }

    @Test func minimumWallpaperCanvasRemainsUsableWithoutPermanentInspector() {
        let canvasWidth = MacFlowMetrics.minimumWindowWidth
            - MacFlowMetrics.sidebarWidth
        #expect(canvasWidth >= 620)
    }

    @Test func notchContentSizesProduceThreeDistinctCompactGeometries() {
        #expect(NotchLayoutMetrics.bodySize(for: .small) == CGSize(width: 320, height: 42))
        #expect(NotchLayoutMetrics.bodySize(for: .medium) == CGSize(width: 440, height: 54))
        #expect(NotchLayoutMetrics.bodySize(for: .large) == CGSize(width: 540, height: 66))

        let sizes = NotchSize.allCases.map {
            (
                NotchLayoutMetrics.bodySize(for: $0),
                NowPlayingMetrics.compactHeight(for: $0),
                NowPlayingMetrics.compactBodyWidth(for: $0)
            )
        }

        #expect(sizes[0].0.width < sizes[1].0.width)
        #expect(sizes[1].0.width < sizes[2].0.width)
        #expect(sizes[0].1 < sizes[1].1)
        #expect(sizes[1].1 < sizes[2].1)
        #expect(sizes[0].2 < sizes[1].2)
        #expect(sizes[1].2 < sizes[2].2)
        #expect(sizes.allSatisfy { $0.0.width == $0.2 })
        #expect(sizes.allSatisfy { $0.0.height == $0.1 })
        #expect(LiveActivityChipMetrics.compactSize == sizes[0].0)
        #expect(LiveActivityChipMetrics.mediumSize == sizes[1].0)
        #expect(LiveActivityChipMetrics.largeSize == sizes[2].0)
        #expect(WallpaperSceneNotchMetrics.compactSize == sizes[0].0)
        #expect(WallpaperSceneNotchMetrics.mediumSize == sizes[1].0)
        #expect(WallpaperSceneNotchMetrics.largeSize == sizes[2].0)
    }

    @Test func appMotionUsesTheDocumentedDurationScale() {
        #expect(AppMotion.Duration.instant == 0.10)
        #expect(AppMotion.Duration.quick == 0.16)
        #expect(AppMotion.Duration.standard == 0.22)
        #expect(AppMotion.Duration.emphasized == 0.34)
    }

    @MainActor
    @Test func hoverOwnershipMovesBetweenDisplaysWithoutAStaleExit() {
        let state = AppState(settings: NotchSettings())

        state.mouseEntered(displayID: 11, allowsExpansion: false)
        #expect(state.isHovering)
        #expect(state.activeDisplayID == 11)

        state.mouseEntered(displayID: 22, allowsExpansion: false)
        state.mouseExited(displayID: 11)
        #expect(state.isHovering)
        #expect(state.activeDisplayID == 22)

        state.mouseExited(displayID: 22)
        #expect(!state.isHovering)
        #expect(state.activeDisplayID == nil)
    }

    @MainActor
    @Test func notchResolverKeepsEventPriorityConsistentAcrossRenderingAndHitTesting() {
        var input = presentationInput()
        input.eventRoute = .call
        input.hasCall = true
        input.isSceneDropTargetVisible = true
        input.isFileDropTargetVisible = true
        input.hasMedia = true

        #expect(NotchPresentationResolver.branchKey(for: input) == "call")

        input.eventRoute = nil
        input.hasCall = false
        #expect(NotchPresentationResolver.branchKey(for: input) == "scene-drop-target")

        input.isSceneDropTargetVisible = false
        #expect(NotchPresentationResolver.branchKey(for: input) == "file-shelf-drop-target")
    }

    @Test func presentationMachineRestoresTheInterruptedActivity() {
        var machine = NotchPresentationMachine()
        #expect(machine.transition(to: "collapsed-music").kind == .initial)

        let call = machine.transition(to: "call")
        #expect(call.kind == .interruption)
        #expect(call.interruptedBranch == "collapsed-music")

        let restored = machine.transition(to: "collapsed-music")
        #expect(restored.kind == .restoration)
        #expect(machine.interruptionStack.isEmpty)
    }

    @Test func presentationMachineSupportsNestedPriorityInterruptions() {
        var machine = NotchPresentationMachine()
        machine.synchronize(to: "collapsed-music")
        #expect(machine.transition(to: "scene-drop-target").kind == .interruption)
        #expect(machine.transition(to: "call").kind == .interruption)
        #expect(machine.transition(to: "scene-drop-target").kind == .restoration)
        #expect(machine.transition(to: "collapsed-music").kind == .restoration)
    }

    @Test func displaySelectionPoliciesUseStableDisplayIdentifiersAndFallbacks() {
        let builtIn = DisplaySnapshot(
            id: 11,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
            scaleFactor: 2,
            isBuiltIn: true,
            isMain: true,
            hasHardwareNotch: true
        )
        let external = DisplaySnapshot(
            id: 22,
            name: "External",
            frame: CGRect(x: 1_440, y: 0, width: 2_560, height: 1_440),
            visibleFrame: CGRect(x: 1_440, y: 0, width: 2_560, height: 1_415),
            scaleFactor: 1,
            isBuiltIn: false,
            isMain: false,
            hasHardwareNotch: false
        )
        let displays = [builtIn, external]

        #expect(DisplaySelectionResolver.selectedIDs(
            policy: .internalDisplay,
            selectedIDs: [],
            displays: displays
        ) == [11])
        #expect(DisplaySelectionResolver.selectedIDs(
            policy: .selectedDisplays,
            selectedIDs: [22],
            displays: displays
        ) == [22])
        #expect(DisplaySelectionResolver.selectedIDs(
            policy: .allDisplays,
            selectedIDs: [],
            displays: displays
        ) == [11, 22])
        #expect(DisplaySelectionResolver.selectedIDs(
            policy: .selectedDisplays,
            selectedIDs: [999],
            displays: displays
        ) == [11])
    }

    @Test func perDisplayNotchConfigurationRoundTripsWithoutScreenObjects() throws {
        let original: [String: DisplayNotchConfiguration] = [
            "11": DisplayNotchConfiguration(contentSize: .small, horizontalOffset: 0),
            "22": DisplayNotchConfiguration(contentSize: .large, horizontalOffset: -36)
        ]

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(
            [String: DisplayNotchConfiguration].self,
            from: data
        )

        #expect(restored == original)
        #expect(restored["22"]?.contentSize == .large)
        #expect(restored["22"]?.horizontalOffset == -36)
    }

    @MainActor
    @Test func expandedNotchOwnsPresentationBeforeBackgroundActivities() {
        var input = presentationInput()
        input.isExpanded = true
        input.eventRoute = .liveActivity
        input.liveActivityBranchKey = "activity"
        input.hasHUD = true

        #expect(NotchPresentationResolver.branchKey(for: input) == "expanded-widget")

        input.isEventDetailPresented = true
        input.hasTrackedEvent = true
        #expect(NotchPresentationResolver.branchKey(for: input) == "expanded-event-detail")
    }

    @MainActor
    @Test func walletAndWallpaperDropUseTheirCanonicalShellGeometry() {
        var input = geometryInput(branchKey: "wallet-contribution")
        let wallet = NotchLayoutCoordinator.visibleSize(for: input)
        #expect(wallet.width == max(input.baseBodySize.width, WalletContributionChipMetrics.width) + 22)
        #expect(wallet.height == WalletContributionChipMetrics.height)

        input.branchKey = "scene-drop-target"
        let drop = NotchLayoutCoordinator.visibleSize(for: input)
        #expect(drop.width == max(input.baseBodySize.width, WallpaperSceneNotchMetrics.dropSize.width) + 22)
        #expect(drop.height == WallpaperSceneNotchMetrics.dropSize.height)
    }

    @MainActor
    @Test func compactMediaAndBareHoverUseDifferentShoulderGeometry() {
        #expect(
            NotchLayoutCoordinator.invertedRadius(
                for: "collapsed-music",
                isHovering: false
            ) == NotchLayoutCoordinator.musicInvertedRadius
        )
        #expect(
            NotchLayoutCoordinator.invertedRadius(
                for: "collapsed-bare",
                isHovering: true
            ) == NotchLayoutCoordinator.hoverInvertedRadius
        )
    }

    @MainActor
    @Test func menuBarBrandMarkUsesNativeTemplateRendering() {
        let image = MacFlowMenuBarSymbol.image()
        #expect(image.isTemplate)
        #expect(image.size.width == 22)
        #expect(image.size.height == 17)
    }

    @Test func wheelImpulseCreatesGlideAndSettles() {
        let engine = MouseFreeScrollEngine()
        engine.addInput(x: 0, y: 1, timestamp: 1, configuration: balanced)

        var travelled: Int32 = 0
        for _ in 0..<240 {
            travelled += engine.update(
                deltaTime: 1.0 / 120.0,
                configuration: balanced
            )?.y ?? 0
        }

        #expect(travelled > 0)
        #expect(!engine.isAnimating)
    }

    @Test func directionChangeCancelsOldMomentumImmediately() {
        let engine = MouseFreeScrollEngine()
        engine.addInput(x: 0, y: 1, timestamp: 1, configuration: balanced)
        for _ in 0..<8 {
            _ = engine.update(deltaTime: 1.0 / 120.0, configuration: balanced)
        }

        engine.addInput(x: 0, y: -1, timestamp: 1.08, configuration: balanced)
        var movementAfterReversal: Int32 = 0
        for _ in 0..<4 {
            movementAfterReversal += engine.update(
                deltaTime: 1.0 / 120.0,
                configuration: balanced
            )?.y ?? 0
        }

        #expect(movementAfterReversal < 0)
    }

    @Test func scrollDistanceRemainsStableAcrossRefreshRates() {
        let at60Hz = simulatedTravel(frameRate: 60)
        let at120Hz = simulatedTravel(frameRate: 120)
        #expect(abs(at60Hz - at120Hz) <= 3)
    }

    @MainActor
    @Test func mouseFreePresetPersistsInsideMacFlowDomain() {
        let suite = "MacFlowIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let controller = MouseFreeController(defaults: defaults, trustProvider: { false })
        controller.apply(.glide)

        let restored = MouseFreeController(defaults: defaults, trustProvider: { false })
        #expect(restored.selectedPreset == .glide)
        #expect(restored.speed == MouseScrollPreset.glide.configuration.speed)
        #expect(restored.smoothness == MouseScrollPreset.glide.configuration.smoothness)
        #expect(restored.acceleration == MouseScrollPreset.glide.configuration.acceleration)
    }

    @MainActor
    @Test func enabledMouseFreeDoesNotStartWithoutAccessibility() {
        let suite = "MacFlowPermissionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "macflow.mouseFree.enabled")

        let controller = MouseFreeController(defaults: defaults, trustProvider: { false })
        controller.start()
        defer { controller.stop() }

        #expect(controller.status == .needsAccessibility)
        #expect(!controller.isAccessibilityTrusted)
    }

    private func simulatedTravel(frameRate: Int) -> Int {
        let engine = MouseFreeScrollEngine()
        engine.addInput(x: 0, y: 1, timestamp: 1, configuration: balanced)

        var travelled: Int32 = 0
        for _ in 0..<(frameRate * 2) {
            travelled += engine.update(
                deltaTime: 1.0 / Double(frameRate),
                configuration: balanced
            )?.y ?? 0
        }
        return Int(travelled)
    }

    @MainActor
    private func presentationInput() -> NotchPresentationResolutionInput {
        NotchPresentationResolutionInput(
            hasCompletedOnboarding: true,
            didRevealOnboarding: true,
            isExpanded: false,
            screenLockBranchKey: nil,
            eventRoute: nil,
            hasCall: false,
            isSceneDropTargetVisible: false,
            isFileDropTargetVisible: false,
            batteryBranchKey: nil,
            focusBranchKey: nil,
            hasWalletContribution: false,
            hasImportantEvent: false,
            isEventDetailPresented: false,
            hasTrackedEvent: false,
            liveActivityBranchKey: nil,
            hasHUD: false,
            hasEvent: false,
            hasMedia: false,
            hasScene: false
        )
    }

    @MainActor
    private func geometryInput(branchKey: String) -> NotchContentLayoutRequest {
        NotchContentLayoutRequest(
            branchKey: branchKey,
            baseBodySize: CGSize(width: 304, height: 32),
            expandedFallbackBodySize: CalendarNotchMetrics.expandedSize,
            onboardingBodySize: OnboardingMetrics.expandedStepSize,
            expandedWidgetBodySize: NotchWidgetMetrics.expandedSize,
            batteryBodyWidth: BatteryAlertMetrics.chargingWidth,
            callBodySize: CallOverlayMetrics.incomingSize,
            mediaPreferredWidth: NowPlayingMetrics.collapsedWidth,
            compactSize: .small,
            isHovering: false,
            showsCollapsedMusicMarquee: false
        )
    }
}
