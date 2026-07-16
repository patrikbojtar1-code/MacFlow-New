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
        #expect(MacFlowMetrics.minimumWindowWidth <= 900)
        #expect(MacFlowMetrics.minimumWindowHeight <= 620)
        #expect(MacFlowMetrics.readableContentMaxWidth >= MacFlowMetrics.idealWindowWidth - MacFlowMetrics.sidebarWidth)
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

    @Test func minimumWallpaperCanvasRemainsUsableBesideInspector() {
        let canvasWidth = MacFlowMetrics.minimumWindowWidth
            - MacFlowMetrics.sidebarWidth
            - MacFlowMetrics.inspectorWidth
            - 2
        #expect(canvasWidth >= 450)
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
}
