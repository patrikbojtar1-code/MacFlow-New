//
//  WallpaperSceneTests.swift
//  NotchLandTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NotchLand

struct WallpaperSceneTests {
    @Test func browserSearchMatchesSceneTitleAndAuthor() {
        let aurora = WallpaperScene(title: "Aurora Drift", author: "MacFlow Studio", kind: .video, assetFilename: "aurora.mp4")
        let coast = WallpaperScene(title: "Quiet Coast", author: "Patrik", kind: .image, assetFilename: "coast.heic")

        let titleMatch = WallpaperBrowserState.filteredScenes([aurora, coast], query: "aurora", scope: .all, sort: .title)
        let authorMatch = WallpaperBrowserState.filteredScenes([aurora, coast], query: "patrik", scope: .all, sort: .title)

        #expect(titleMatch.map(\.id) == [aurora.id])
        #expect(authorMatch.map(\.id) == [coast.id])
    }

    @Test func browserScopesRespectKindFavoritesAndCollections() {
        let live = WallpaperScene(title: "Live", kind: .video, assetFilename: "live.mov")
        let still = WallpaperScene(title: "Still", kind: .image, assetFilename: "still.png")

        #expect(WallpaperBrowserState.filteredScenes([live, still], query: "", scope: .video, sort: .title).map(\.id) == [live.id])
        #expect(WallpaperBrowserState.filteredScenes([live, still], query: "", scope: .still, sort: .title).map(\.id) == [still.id])
        #expect(WallpaperBrowserState.filteredScenes([live, still], query: "", scope: .favorites, sort: .title, favoriteIDs: [still.id]).map(\.id) == [still.id])
        #expect(WallpaperBrowserState.filteredScenes([live, still], query: "", scope: .collection(UUID()), sort: .title, collectionIDs: [live.id]).map(\.id) == [live.id])
    }

    @Test func browserSortingIsStableAndPurposeful() {
        let earlier = WallpaperScene(title: "Zulu", kind: .image, assetFilename: "zulu.png", createdAt: .distantPast)
        let later = WallpaperScene(title: "Alpha", kind: .video, assetFilename: "alpha.mov", createdAt: .distantFuture)

        #expect(WallpaperBrowserState.filteredScenes([earlier, later], query: "", scope: .all, sort: .recent).map(\.id) == [later.id, earlier.id])
        #expect(WallpaperBrowserState.filteredScenes([earlier, later], query: "", scope: .all, sort: .title).map(\.id) == [later.id, earlier.id])
    }

    @Test func browserPreservesManualPlaylistOrder() {
        let first = WallpaperScene(title: "First", kind: .image, assetFilename: "first.png")
        let second = WallpaperScene(title: "Second", kind: .image, assetFilename: "second.png")
        let third = WallpaperScene(title: "Third", kind: .video, assetFilename: "third.mov")
        let order = [third.id, first.id, second.id]

        let result = WallpaperBrowserState.filteredScenes(
            [first, second, third],
            query: "",
            scope: .collection(UUID()),
            sort: .playlist,
            collectionIDs: Set(order),
            collectionOrder: order
        )

        #expect(result.map(\.id) == order)
    }

    @Test func playlistLibrarySupportsOrderedMoves() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MacFlowPlaylistTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let firstURL = root.appendingPathComponent("First.png")
        let secondURL = root.appendingPathComponent("Second.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: firstURL)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: secondURL)

        let library = WallpaperSceneLibrary(
            rootDirectory: root.appendingPathComponent("Library", isDirectory: true)
        )
        let first = try await library.importScene(from: firstURL)
        let second = try await library.importScene(from: secondURL)
        let playlist = try #require(library.createCollection(named: "Evening"))
        library.add(first, to: playlist)
        library.add(second, to: playlist)

        var latest = try #require(library.collections.first { $0.id == playlist.id })
        #expect(library.scenes(in: latest).map(\.id) == [first.id, second.id])

        library.moveScenes(in: latest, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        latest = try #require(library.collections.first { $0.id == playlist.id })
        #expect(library.scenes(in: latest).map(\.id) == [second.id, first.id])
    }

    @MainActor
    @Test func wallpaperHubRendersAtCompanionWindowSize() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MacFlowHubSnapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let fixtures: [(String, NSColor, NSColor)] = [
            ("Midnight Summit", .systemIndigo, .black),
            ("Emerald Valley", .systemGreen, .darkGray),
            ("Solar Dunes", .systemOrange, .systemBrown),
            ("Pacific Motion", .systemTeal, .systemBlue),
        ]
        let library = WallpaperSceneLibrary(
            rootDirectory: root.appendingPathComponent("Library", isDirectory: true)
        )
        for fixture in fixtures {
            let url = root.appendingPathComponent("\(fixture.0).png")
            try Self.writeGradientPNG(to: url, colors: [fixture.1, fixture.2])
            _ = try await library.importScene(from: url)
        }

        if let selectedScene = library.scenes.first {
            try library.updateRendering(
                forSceneID: selectedScene.id,
                configuration: WallpaperSceneRenderingConfiguration(
                    motionPreset: .slowDrift,
                    ambientEffect: .embers,
                    effectIntensity: 0.8,
                    parallaxStrength: 0.4,
                    musicReaction: .playbackPulse,
                    musicReactionIntensity: 0.7
                )
            )
        }

        let defaults = try #require(UserDefaults(suiteName: "MacFlowHubSnapshot.\(UUID().uuidString)"))
        let controller = WallpaperSceneController(
            library: library,
            performance: WallpaperPerformanceMonitor(defaults: defaults),
            displayCoordinator: DisplayCoordinator(),
            defaults: defaults
        )
        let rootView = ScenesSettingsView()
            .environmentObject(controller)
            .frame(width: 1_040, height: 680)
            .background(MacFlowColor.canvas)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_040, height: 680)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let outputDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/WallpaperHubScreenshots", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("wallpaper-hub.png")
        try png.write(to: outputURL, options: .atomic)
        #expect(fileManager.fileExists(atPath: outputURL.path))
    }

    @MainActor
    @Test func smartRotationEditorRendersPlaylistAndContextRules() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MacFlowAutomationSnapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let library = WallpaperSceneLibrary(
            rootDirectory: root.appendingPathComponent("Library", isDirectory: true)
        )
        for (title, color) in [("Deep Focus", NSColor.systemIndigo), ("Battery Calm", .systemGreen)] {
            let url = root.appendingPathComponent("\(title).png")
            try Self.writeGradientPNG(to: url, colors: [color, .black])
            _ = try await library.importScene(from: url)
        }
        let playlist = try #require(library.createCollection(named: "Workday Flow"))
        for scene in library.scenes.reversed() {
            library.add(scene, to: playlist)
        }

        let suiteName = "MacFlowAutomationSnapshot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = WallpaperSceneController(
            library: library,
            performance: WallpaperPerformanceMonitor(defaults: defaults),
            displayCoordinator: DisplayCoordinator(),
            defaults: defaults
        )
        controller.updateAutomationConfiguration {
            $0.isEnabled = true
            $0.rotationSource = .playlist
            $0.rotationPlaylistID = playlist.id
            $0.focusSceneID = library.scenes.first?.id
            $0.lowPowerSceneID = library.scenes.last?.id
        }

        let rootView = WallpaperAutomationEditor()
            .environmentObject(controller)
            .frame(width: 720, height: 680)
            .background(MacFlowColor.canvas)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 680)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let outputDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/WallpaperHubScreenshots", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("smart-rotation.png")
        try png.write(to: outputURL, options: .atomic)
        #expect(fileManager.fileExists(atPath: outputURL.path))
    }

    @MainActor
    @Test func importingForPreviewDoesNotApplyTheScene() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MacFlowPreviewImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Preview.png")
        try Self.writeGradientPNG(to: source, colors: [.systemPurple, .black])

        let suiteName = "MacFlowPreviewImport.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = WallpaperSceneController(
            library: WallpaperSceneLibrary(
                rootDirectory: root.appendingPathComponent("Library", isDirectory: true)
            ),
            performance: WallpaperPerformanceMonitor(defaults: defaults),
            displayCoordinator: DisplayCoordinator(),
            defaults: defaults
        )

        let imported = await controller.importScene(from: source)
        #expect(imported != nil)
        #expect(controller.activeSceneID == nil)
        #expect(!controller.isRunning)
    }

    @MainActor
    @Test func wallpaperDisplayTargetsPersistAcrossControllerInstances() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MacFlowDisplayTargets-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let suiteName = "MacFlowDisplayTargets.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = WallpaperSceneController(
            library: WallpaperSceneLibrary(rootDirectory: root),
            performance: WallpaperPerformanceMonitor(defaults: defaults),
            displayCoordinator: DisplayCoordinator(),
            defaults: defaults
        )
        first.setDisplayPolicy(.selectedDisplays)
        first.toggleTargetDisplay(41)
        first.toggleTargetDisplay(73)

        let second = WallpaperSceneController(
            library: WallpaperSceneLibrary(rootDirectory: root),
            performance: WallpaperPerformanceMonitor(defaults: defaults),
            displayCoordinator: DisplayCoordinator(),
            defaults: defaults
        )
        #expect(second.displayPolicy == .selectedDisplays)
        #expect(second.selectedDisplayIDs == [41, 73])
    }

    @MainActor
    private static func writeGradientPNG(to url: URL, colors: [NSColor]) throws {
        let image = NSImage(size: NSSize(width: 640, height: 360))
        image.lockFocus()
        NSGradient(colors: colors)?.draw(
            in: NSRect(x: 0, y: 0, width: 640, height: 360),
            angle: 22
        )
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }

    @MainActor
    @Test func focusMonitorCanBeEnabledAndDisabledWithoutDuplicateRegistration() {
        let controller = FocusModeController()

        controller.setMonitoring(true)
        controller.setMonitoring(true)
        #expect(controller.authorizationStatus == .monitoring)

        controller.setMonitoring(false)
        #expect(controller.authorizationStatus == .stopped)
        #expect(controller.currentPresentation == nil)
        #expect(!controller.isFocusActive)
    }

    @Test func supportedFilesNormalizeToTheCorrectSceneKind() {
        #expect(WallpaperSceneFileSupport.kind(for: URL(fileURLWithPath: "/tmp/Scene.HEIC")) == .image)
        #expect(WallpaperSceneFileSupport.kind(for: URL(fileURLWithPath: "/tmp/Scene.MP4")) == .video)
        #expect(WallpaperSceneFileSupport.kind(for: URL(fileURLWithPath: "/tmp/Scene.html")) == nil)
    }

    @Test func performanceProfilesExposeStableBudgets() {
        #expect(WallpaperPerformanceProfile.eco.targetFramesPerSecond == 24)
        #expect(WallpaperPerformanceProfile.balanced.targetFramesPerSecond == 30)
        #expect(WallpaperPerformanceProfile.cinematic.targetFramesPerSecond == 60)
    }

    @Test func automaticWallpaperProfilePrioritizesThermalEfficiency() {
        #expect(WallpaperPerformanceMonitor.resolvedProfile(
            selected: .automatic,
            isLowPowerModeEnabled: false,
            thermalState: .nominal
        ) == .balanced)
        #expect(WallpaperPerformanceMonitor.resolvedProfile(
            selected: .automatic,
            isLowPowerModeEnabled: true,
            thermalState: .nominal
        ) == .eco)
        #expect(WallpaperPerformanceMonitor.shouldSuspendVideo(for: .serious))
        #expect(WallpaperPerformanceMonitor.shouldSuspendVideo(for: .critical))
    }

    @Test func globalNotchSizeKeepsDisplayOffsetsAndSynchronizesDensity() {
        let configurations: [UInt32: DisplayNotchConfiguration] = [
            1: DisplayNotchConfiguration(contentSize: .small, horizontalOffset: -24),
            2: DisplayNotchConfiguration(contentSize: .medium, horizontalOffset: 32),
        ]

        let updated = NotchSettings.configurations(
            applyingGlobalContentSize: .large,
            to: configurations
        )

        #expect(updated.values.allSatisfy { $0.contentSize == .large })
        #expect(updated[1]?.horizontalOffset == -24)
        #expect(updated[2]?.horizontalOffset == 32)
    }

    @Test func renderingProfilesClampToEngineBudgets() {
        let configuration = WallpaperSceneRenderingConfiguration(
            scalingMode: .fit,
            playbackRate: 9,
            dimming: 4,
            motionPreset: .slowDrift,
            saturation: 9,
            contrast: 0,
            vignette: 2,
            ambientEffect: .embers,
            effectIntensity: 4,
            parallaxStrength: 3,
            musicReaction: .playbackPulse,
            musicReactionIntensity: 2,
            composerLayers: [
                .init(
                    kind: .atmosphere,
                    opacity: 4,
                    blendMode: .add,
                    scale: 4,
                    offsetX: -2,
                    offsetY: 3,
                    blurRadius: 100,
                    maskStyle: .focusCenter,
                    maskFeather: 4,
                    isMaskInverted: true,
                    animationPreset: .float,
                    animationAmount: 4,
                    animationDuration: 90
                ),
                .init(kind: .atmosphere, isVisible: false),
                .init(kind: .media, opacity: -2),
            ]
        ).normalized

        #expect(configuration.scalingMode == .fit)
        #expect(configuration.playbackRate == 1.5)
        #expect(configuration.dimming == 0.7)
        #expect(configuration.motionPreset == .slowDrift)
        #expect(configuration.saturation == 1.4)
        #expect(configuration.contrast == 0.8)
        #expect(configuration.vignette == 0.65)
        #expect(configuration.ambientEffect == .embers)
        #expect(configuration.effectIntensity == 1)
        #expect(configuration.parallaxStrength == 1)
        #expect(configuration.musicReaction == .playbackPulse)
        #expect(configuration.musicReactionIntensity == 1)
        #expect(configuration.composerLayers.map(\.kind) == [
            .atmosphere, .media, .musicGlow, .vignette, .dimming,
        ])
        #expect(configuration.composerLayers[0].opacity == 1)
        #expect(configuration.composerLayers[0].scale == 1.3)
        #expect(configuration.composerLayers[0].offsetX == -0.25)
        #expect(configuration.composerLayers[0].offsetY == 0.25)
        #expect(configuration.composerLayers[0].blurRadius == 18)
        #expect(configuration.composerLayers[0].maskStyle == .focusCenter)
        #expect(configuration.composerLayers[0].maskFeather == 0.9)
        #expect(configuration.composerLayers[0].isMaskInverted)
        #expect(configuration.composerLayers[0].animationPreset == .float)
        #expect(configuration.composerLayers[0].animationAmount == 1)
        #expect(configuration.composerLayers[0].animationDuration == 20)
        #expect(configuration.composerLayers[1].opacity == 0)
    }

    @Test func composerPresetsPreserveMediaSettingsAndStayWithinBudgets() {
        let source = WallpaperSceneRenderingConfiguration(
            scalingMode: .fit,
            playbackRate: 1.25,
            dimming: 0.4
        )

        for preset in WallpaperSceneComposerPreset.allCases {
            let imageRendering = preset.applying(to: source, sceneKind: .image)
            #expect(imageRendering.scalingMode == .fit)
            #expect(imageRendering.playbackRate == 1.25)
            #expect(imageRendering == imageRendering.normalized)
            #expect(preset.matches(imageRendering, sceneKind: .image))

            let videoRendering = preset.applying(to: source, sceneKind: .video)
            #expect(videoRendering.scalingMode == .fit)
            #expect(videoRendering.playbackRate == 1.25)
            #expect(videoRendering.motionPreset == .none)
            #expect(preset.matches(videoRendering, sceneKind: .video))
        }
    }

    @Test func manualComposerChangeLeavesPresetState() {
        let preset = WallpaperSceneComposerPreset.snowNight
        let applied = preset.applying(to: .default, sceneKind: .image)
        #expect(preset.matches(applied, sceneKind: .image))
        #expect(applied.ambientEffect == .snow)

        var customized = applied
        customized.effectIntensity = 0.31
        #expect(!preset.matches(customized, sceneKind: .image))
    }

    @Test func legacyRenderingConfigurationMigratesSceneStudioDefaults() throws {
        let json = """
        {
          "scalingMode": "fit",
          "playbackRate": 1.25,
          "dimming": 0.2
        }
        """
        let rendering = try JSONDecoder().decode(
            WallpaperSceneRenderingConfiguration.self,
            from: Data(json.utf8)
        )

        #expect(rendering.scalingMode == .fit)
        #expect(rendering.motionPreset == .none)
        #expect(rendering.saturation == 1)
        #expect(rendering.contrast == 1)
        #expect(rendering.vignette == 0)
        #expect(rendering.ambientEffect == .none)
        #expect(rendering.effectIntensity == 0.45)
        #expect(rendering.parallaxStrength == 0)
        #expect(rendering.musicReaction == .none)
        #expect(rendering.musicReactionIntensity == 0.45)
        #expect(rendering.composerLayers == WallpaperSceneRenderingConfiguration.defaultComposerLayers)
    }

    @Test func legacyComposerLayersMigrateToNeutralTransforms() throws {
        let json = """
        {
          "composerLayers": [
            {
              "kind": "media",
              "isVisible": true,
              "opacity": 0.8,
              "blendMode": "normal"
            }
          ]
        }
        """
        let rendering = try JSONDecoder().decode(
            WallpaperSceneRenderingConfiguration.self,
            from: Data(json.utf8)
        )
        let media = try #require(rendering.composerLayers.first)

        #expect(media.kind == .media)
        #expect(media.opacity == 0.8)
        #expect(media.hasDefaultTransform)
        #expect(media.hasDefaultMask)
        #expect(media.hasDefaultAnimation)
        #expect(rendering.composerLayers.count == 5)
    }

    @Test func sceneMotionPolicyProtectsEnergyAndAccessibilityBudgets() {
        #expect(WallpaperSceneMotionPolicy.shouldAnimate(
            preset: .cinematicZoom,
            kind: .image,
            profile: .balanced,
            reduceMotion: false,
            paused: false
        ))
        #expect(!WallpaperSceneMotionPolicy.shouldAnimate(
            preset: .slowDrift,
            kind: .image,
            profile: .eco,
            reduceMotion: false,
            paused: false
        ))
        #expect(!WallpaperSceneMotionPolicy.shouldAnimate(
            preset: .slowDrift,
            kind: .video,
            profile: .cinematic,
            reduceMotion: false,
            paused: false
        ))
        #expect(!WallpaperSceneMotionPolicy.shouldAnimate(
            preset: .slowDrift,
            kind: .image,
            profile: .cinematic,
            reduceMotion: true,
            paused: false
        ))
    }

    @Test func sceneComposerPolicyProtectsEnergyAndAccessibilityBudgets() {
        #expect(WallpaperSceneEffectsPolicy.shouldRender(
            effect: .snow,
            profile: .balanced,
            reduceMotion: false,
            paused: false
        ))
        #expect(WallpaperSceneEffectsPolicy.shouldRender(
            effect: .embers,
            profile: .eco,
            reduceMotion: false,
            paused: false
        ))
        #expect(!WallpaperSceneEffectsPolicy.shouldRender(
            effect: .dust,
            profile: .cinematic,
            reduceMotion: true,
            paused: false
        ))
        #expect(WallpaperSceneEffectsPolicy.shouldTrackPointer(
            strength: 0.4,
            profile: .cinematic,
            reduceMotion: false,
            paused: false
        ))
        #expect(!WallpaperSceneEffectsPolicy.shouldTrackPointer(
            strength: 0,
            profile: .cinematic,
            reduceMotion: false,
            paused: false
        ))
        #expect(WallpaperSceneEffectsPolicy.densityMultiplier(for: .eco) > 0)
        #expect(
            WallpaperSceneEffectsPolicy.densityMultiplier(for: .eco)
                < WallpaperSceneEffectsPolicy.densityMultiplier(for: .balanced)
        )
        #expect(
            WallpaperSceneEffectsPolicy.maximumAnimatedLayers(for: .eco)
                < WallpaperSceneEffectsPolicy.maximumAnimatedLayers(for: .cinematic)
        )
        #expect(
            WallpaperSceneEffectsPolicy.animationAmountMultiplier(for: .eco)
                < WallpaperSceneEffectsPolicy.animationAmountMultiplier(for: .balanced)
        )
    }

    @Test func musicReactionRequiresPlaybackAndRespectsEnergyPolicy() {
        #expect(WallpaperMusicReactionPolicy.shouldAnimate(
            reaction: .ambientGlow,
            isPlaying: true,
            profile: .balanced,
            reduceMotion: false,
            paused: false
        ))
        #expect(!WallpaperMusicReactionPolicy.shouldAnimate(
            reaction: .playbackPulse,
            isPlaying: false,
            profile: .cinematic,
            reduceMotion: false,
            paused: false
        ))
        #expect(WallpaperMusicReactionPolicy.shouldAnimate(
            reaction: .playbackPulse,
            isPlaying: true,
            profile: .eco,
            reduceMotion: false,
            paused: false
        ))
        #expect(!WallpaperMusicReactionPolicy.shouldAnimate(
            reaction: .ambientGlow,
            isPlaying: true,
            profile: .cinematic,
            reduceMotion: true,
            paused: false
        ))
        #expect(
            WallpaperMusicReactionPolicy.intensityMultiplier(for: .eco)
                < WallpaperMusicReactionPolicy.intensityMultiplier(for: .balanced)
        )
    }

    @MainActor
    @Test func desktopRendererInstallsAndPausesComposerEffects() async throws {
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeEffects-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: assetURL) }
        try Self.writeGradientPNG(to: assetURL, colors: [.systemBlue, .black])

        let rendering = WallpaperSceneRenderingConfiguration(
            ambientEffect: .snow,
            effectIntensity: 0.8,
            musicReaction: .playbackPulse,
            musicReactionIntensity: 0.7
        )
        let scene = WallpaperScene(
            title: "Runtime Effects",
            kind: .image,
            assetFilename: "missing-runtime-fixture.png",
            rendering: rendering
        )
        let renderer = WallpaperSceneRenderView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 360)
        )
        defer { renderer.stop() }

        renderer.display(
            scene: scene,
            assetURL: assetURL,
            profile: .eco
        )
        try await Task.sleep(for: .milliseconds(80))
        var diagnostics = renderer.effectDiagnostics
        #expect(diagnostics.ambientLayerAttached)
        #expect(diagnostics.ambientParticleBirthRate > 0)
        #expect(!diagnostics.musicGlowAnimating)
        #expect(diagnostics.composerLayerOrder == rendering.composerLayers.map(\.kind))

        renderer.update(mediaPlayback: WallpaperMediaPlaybackSnapshot(
            isPlaying: true,
            accentRed: 0.2,
            accentGreen: 0.6,
            accentBlue: 1
        ))
        diagnostics = renderer.effectDiagnostics
        #expect(diagnostics.musicGlowAnimating)

        var customizedLayers = rendering
        customizedLayers.composerLayers.swapAt(0, 2)
        if let atmosphereIndex = customizedLayers.composerLayers.firstIndex(where: {
            $0.kind == .atmosphere
        }) {
            customizedLayers.composerLayers[atmosphereIndex].isVisible = false
        }
        if let mediaIndex = customizedLayers.composerLayers.firstIndex(where: {
            $0.kind == .media
        }) {
            customizedLayers.composerLayers[mediaIndex].scale = 1.12
            customizedLayers.composerLayers[mediaIndex].offsetX = 0.08
            customizedLayers.composerLayers[mediaIndex].blurRadius = 6
            customizedLayers.composerLayers[mediaIndex].maskStyle = .focusCenter
            customizedLayers.composerLayers[mediaIndex].maskFeather = 0.62
            customizedLayers.composerLayers[mediaIndex].animationPreset = .breathe
            customizedLayers.composerLayers[mediaIndex].animationAmount = 0.7
            customizedLayers.composerLayers[mediaIndex].animationDuration = 4
        }
        renderer.update(rendering: customizedLayers)
        try await Task.sleep(for: .milliseconds(220))
        diagnostics = renderer.effectDiagnostics
        #expect(diagnostics.composerLayerOrder == customizedLayers.composerLayers.map(\.kind))
        #expect(diagnostics.hiddenComposerLayers.contains(.atmosphere))
        #expect(diagnostics.transformedComposerLayers.contains(.media))
        #expect(diagnostics.blurredComposerLayers.contains(.media))
        #expect(diagnostics.maskedComposerLayers.contains(.media))
        #expect(diagnostics.animatedComposerLayers.contains(.media))
        #expect(!diagnostics.ambientLayerAttached)

        renderer.setPaused(true)
        diagnostics = renderer.effectDiagnostics
        #expect(!diagnostics.ambientLayerAttached)
        #expect(!diagnostics.musicGlowAnimating)
        #expect(diagnostics.animatedComposerLayers.isEmpty)
    }

    @Test func legacySceneManifestDefaultsToFillAtNormalSpeed() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "Legacy",
          "author": "Creator",
          "kind": "video",
          "assetFilename": "legacy.mp4",
          "createdAt": "2026-07-16T10:00:00Z",
          "manifestVersion": 1
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scene = try decoder.decode(WallpaperScene.self, from: Data(json.utf8))

        #expect(scene.rendering == .default)
    }

    @Test func dayPeriodsUseStableLocalTimeBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func date(hour: Int) -> Date {
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 16,
                hour: hour
            ))!
        }

        #expect(WallpaperDayPeriod.current(at: date(hour: 5), calendar: calendar) == .morning)
        #expect(WallpaperDayPeriod.current(at: date(hour: 11), calendar: calendar) == .daytime)
        #expect(WallpaperDayPeriod.current(at: date(hour: 17), calendar: calendar) == .evening)
        #expect(WallpaperDayPeriod.current(at: date(hour: 22), calendar: calendar) == .night)
    }

    @Test func favoriteRotationWrapsWithoutDuplicatingBusinessLogic() {
        let first = WallpaperScene(
            title: "First",
            kind: .image,
            assetFilename: "first.png"
        )
        let second = WallpaperScene(
            title: "Second",
            kind: .image,
            assetFilename: "second.png"
        )

        #expect(WallpaperSceneController.nextScene(after: nil, in: [first, second])?.id == first.id)
        #expect(WallpaperSceneController.nextScene(after: first.id, in: [first, second])?.id == second.id)
        #expect(WallpaperSceneController.nextScene(after: second.id, in: [first, second])?.id == first.id)
        #expect(WallpaperSceneController.nextScene(after: first.id, in: []) == nil)
    }

    @Test func automationConfigurationRoundTripsEveryRule() throws {
        let focusID = UUID()
        let lowPowerID = UUID()
        let morningID = UUID()
        let playlistID = UUID()
        var configuration = WallpaperAutomationConfiguration()
        configuration.isEnabled = true
        configuration.rotationIntervalMinutes = 15
        configuration.rotationSource = .playlist
        configuration.rotationPlaylistID = playlistID
        configuration.pausesRotationOnLowPower = false
        configuration.focusSceneID = focusID
        configuration.lowPowerSceneID = lowPowerID
        configuration.setSceneID(morningID, for: .morning)

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(WallpaperAutomationConfiguration.self, from: data)

        #expect(decoded == configuration)
        #expect(decoded.focusSceneID == focusID)
        #expect(decoded.lowPowerSceneID == lowPowerID)
        #expect(decoded.rotationPlaylistID == playlistID)
        #expect(decoded.sceneID(for: .morning) == morningID)
    }

    @Test func legacyAutomationConfigurationMigratesSmartRotationDefaults() throws {
        let json = """
        {
          "isEnabled": true,
          "rotatesFavorites": true,
          "rotationIntervalMinutes": 15
        }
        """
        let configuration = try JSONDecoder().decode(
            WallpaperAutomationConfiguration.self,
            from: Data(json.utf8)
        )

        #expect(configuration.rotationSource == .favorites)
        #expect(configuration.rotationPlaylistID == nil)
        #expect(configuration.pausesRotationOnLowPower)
        #expect(configuration.lowPowerSceneID == nil)
    }

    @Test func automationRulesPrioritizeFocusThenPowerThenTime() throws {
        let focusID = UUID()
        let lowPowerID = UUID()
        let eveningID = UUID()
        var configuration = WallpaperAutomationConfiguration()
        configuration.focusSceneID = focusID
        configuration.lowPowerSceneID = lowPowerID
        configuration.setSceneID(eveningID, for: .evening)
        let available: Set<UUID> = [focusID, lowPowerID, eveningID]

        let focus = WallpaperAutomationRuleResolver.firstMatch(
            configuration: configuration,
            availableSceneIDs: available,
            isFocusActive: true,
            isLowPowerModeEnabled: true,
            dayPeriod: .evening
        )
        #expect(focus == WallpaperAutomationRuleMatch(sceneID: focusID, reason: .focus))

        let power = WallpaperAutomationRuleResolver.firstMatch(
            configuration: configuration,
            availableSceneIDs: available,
            isFocusActive: false,
            isLowPowerModeEnabled: true,
            dayPeriod: .evening
        )
        #expect(power == WallpaperAutomationRuleMatch(sceneID: lowPowerID, reason: .lowPower))

        let time = WallpaperAutomationRuleResolver.firstMatch(
            configuration: configuration,
            availableSceneIDs: [eveningID],
            isFocusActive: true,
            isLowPowerModeEnabled: true,
            dayPeriod: .evening
        )
        #expect(time == WallpaperAutomationRuleMatch(
            sceneID: eveningID,
            reason: .dayPeriod(.evening)
        ))
    }

    @Test func packagePathsRejectTraversalAndNestedAssets() {
        #expect(WallpaperScenePackageSecurity.isSafeFilename("asset.mp4"))
        #expect(!WallpaperScenePackageSecurity.isSafeFilename("../asset.mp4"))
        #expect(!WallpaperScenePackageSecurity.isSafeFilename("Media/asset.mp4"))
        #expect(!WallpaperScenePackageSecurity.isSafeFilename("Media\\asset.mp4"))
    }

    @MainActor
    @Test func dropRoutingAcceptsExactlyOneSupportedSceneAsset() {
        #expect(WallpaperSceneController.isSceneDrop([URL(fileURLWithPath: "/tmp/Aurora.heic")]))
        #expect(WallpaperSceneController.isSceneDrop([URL(fileURLWithPath: "/tmp/Ocean.mov")]))
        #expect(!WallpaperSceneController.isSceneDrop([URL(fileURLWithPath: "/tmp/index.html")]))
        #expect(!WallpaperSceneController.isSceneDrop([
            URL(fileURLWithPath: "/tmp/One.png"),
            URL(fileURLWithPath: "/tmp/Two.png"),
        ]))
    }

    @Test func fullscreenDetectorRequiresAVisibleFrontmostWindowMatchingTheDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let fullscreen = WallpaperWindowSnapshot(
            ownerPID: 42,
            layer: 0,
            bounds: display,
            alpha: 1
        )
        let maximized = WallpaperWindowSnapshot(
            ownerPID: 42,
            layer: 0,
            bounds: CGRect(x: 0, y: 24, width: 1_512, height: 958),
            alpha: 1
        )

        #expect(WallpaperFullscreenDetector.isFullscreen(
            frontmostPID: 42,
            windows: [fullscreen],
            displayFrames: [display]
        ))
        #expect(!WallpaperFullscreenDetector.isFullscreen(
            frontmostPID: 42,
            windows: [maximized],
            displayFrames: [display]
        ))
        #expect(!WallpaperFullscreenDetector.isFullscreen(
            frontmostPID: 7,
            windows: [fullscreen],
            displayFrames: [display]
        ))

        let sameSizeOnAnotherDisplay = WallpaperWindowSnapshot(
            ownerPID: 42,
            layer: 0,
            bounds: display.offsetBy(dx: display.width, dy: 0),
            alpha: 1
        )
        #expect(!WallpaperFullscreenDetector.isFullscreen(
            frontmostPID: 42,
            windows: [sameSizeOnAnotherDisplay],
            displayFrames: [display]
        ))
    }

    @MainActor
    @Test func telemetryMeasuresRendererLifecycleAndDirectFirstFrame() {
        let monitor = WallpaperTelemetryMonitor(
            maximumEventCount: 24,
            inspectsAssetMetadata: false
        )
        let scene = WallpaperScene(
            title: "Measured Still",
            kind: .image,
            assetFilename: "measured.png"
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let transitionID = UUID()
        let rendererID = UUID()

        monitor.updateContext(
            scene: scene,
            assetURL: URL(fileURLWithPath: "/tmp/measured.png"),
            displayIDs: [7],
            selectedProfile: .automatic,
            effectiveProfile: .balanced,
            isLowPowerModeEnabled: false,
            thermalState: .nominal,
            isPaused: false,
            pauseReason: nil,
            at: start
        )
        monitor.beginTransition(
            id: transitionID,
            sceneID: scene.id,
            targetDisplayIDs: [7],
            strategy: .direct,
            at: start
        )
        monitor.rendererEvent(
            .rendererCreated(hasPlayer: false),
            rendererID: rendererID,
            displayID: 7,
            transitionID: transitionID,
            at: start
        )
        monitor.rendererEvent(
            .firstFramePresented,
            rendererID: rendererID,
            displayID: 7,
            transitionID: transitionID,
            at: start.addingTimeInterval(0.125)
        )

        #expect(monitor.snapshot.activeRendererCount == 1)
        #expect(monitor.snapshot.activePlayerCount == 0)
        #expect(monitor.snapshot.currentTransition == nil)
        #expect(monitor.snapshot.lastTransition?.phase == .completed)
        #expect(monitor.snapshot.lastTransition?.timeToFirstFrame == 0.125)
        #expect(monitor.snapshot.displays.first?.readiness == .firstFramePresented)

        monitor.rendererEvent(
            .stopped,
            rendererID: rendererID,
            displayID: 7,
            transitionID: transitionID,
            at: start.addingTimeInterval(0.2)
        )
        #expect(monitor.snapshot.activeRendererCount == 0)
    }

    @MainActor
    @Test func telemetryDoesNotMistakeRetiringFramesForNewDisplayReadiness() throws {
        let monitor = WallpaperTelemetryMonitor(inspectsAssetMetadata: false)
        let scene = WallpaperScene(
            title: "Two Displays",
            kind: .video,
            assetFilename: "two-displays.mov"
        )
        let start = Date(timeIntervalSince1970: 2_000)

        monitor.updateContext(
            scene: scene,
            assetURL: URL(fileURLWithPath: "/tmp/two-displays.mov"),
            displayIDs: [1, 2],
            selectedProfile: .balanced,
            effectiveProfile: .balanced,
            isLowPowerModeEnabled: false,
            thermalState: .nominal,
            isPaused: false,
            pauseReason: nil,
            at: start
        )

        let retiredRenderer = UUID()
        monitor.rendererEvent(
            .rendererCreated(hasPlayer: true),
            rendererID: retiredRenderer,
            displayID: 2,
            transitionID: nil,
            at: start
        )
        monitor.rendererEvent(
            .firstFramePresented,
            rendererID: retiredRenderer,
            displayID: 2,
            transitionID: nil,
            at: start
        )

        let transitionID = UUID()
        monitor.beginTransition(
            id: transitionID,
            sceneID: scene.id,
            targetDisplayIDs: [1, 2],
            strategy: .dualRendererCrossfade,
            at: start
        )
        let first = UUID()
        monitor.rendererEvent(
            .rendererCreated(hasPlayer: true),
            rendererID: first,
            displayID: 1,
            transitionID: transitionID,
            at: start
        )
        monitor.rendererEvent(
            .firstFramePresented,
            rendererID: first,
            displayID: 1,
            transitionID: transitionID,
            at: start.addingTimeInterval(0.1)
        )

        #expect(monitor.snapshot.currentTransition?.firstFrameAt == nil)

        let second = UUID()
        monitor.rendererEvent(
            .rendererCreated(hasPlayer: true),
            rendererID: second,
            displayID: 2,
            transitionID: transitionID,
            at: start
        )
        monitor.rendererEvent(
            .firstFramePresented,
            rendererID: second,
            displayID: 2,
            transitionID: transitionID,
            at: start.addingTimeInterval(0.16)
        )

        let firstFrame = try #require(monitor.snapshot.currentTransition?.timeToFirstFrame)
        #expect(abs(firstFrame - 0.16) < 0.001)
        #expect(monitor.snapshot.activePlayerCount == 3)
    }

    @MainActor
    @Test func telemetryBoundsEventsAndRecordsPauseReason() {
        let monitor = WallpaperTelemetryMonitor(
            maximumEventCount: 16,
            inspectsAssetMetadata: false
        )
        for displayID in 1...20 {
            monitor.synchronizeDisplays([UInt32(displayID)])
        }
        monitor.updatePlayback(isPaused: true, reason: .thermalPressure)

        #expect(monitor.recentEvents.count == 16)
        #expect(monitor.snapshot.isPaused)
        #expect(monitor.snapshot.pauseReason == .thermalPressure)
    }

    @MainActor
    @Test func benchmarkRunnerCapturesEventDrivenMaximums() throws {
        let runner = WallpaperBenchmarkRunner()
        let startedAt = Date(timeIntervalSince1970: 3_000)
        runner.begin(.shared4KTwoDisplays, at: startedAt)

        var snapshot = WallpaperTelemetrySnapshot.empty
        snapshot.activeRendererCount = 4
        snapshot.activePlayerCount = 4
        snapshot.estimatedDecodedMemoryBytes = Int64(128 * 1_024 * 1_024)
        snapshot.displays = [
            WallpaperDisplayTelemetry(
                id: 1,
                visibility: .visible,
                rendererCount: 2,
                playerCount: 2,
                readiness: .firstFramePresented,
                isPaused: false,
                pauseReason: nil,
                droppedFrames: 1,
                timeToFirstFrame: 0.2
            ),
            WallpaperDisplayTelemetry(
                id: 2,
                visibility: .visible,
                rendererCount: 2,
                playerCount: 2,
                readiness: .firstFramePresented,
                isPaused: false,
                pauseReason: nil,
                droppedFrames: 0,
                timeToFirstFrame: 0.2
            ),
        ]
        snapshot.droppedFrames = 1
        runner.observe(snapshot)

        let result = try #require(runner.finish(at: startedAt.addingTimeInterval(60)))
        #expect(result.sampleCount == 1)
        #expect(result.maximumRendererCount == 4)
        #expect(result.maximumPlayerCount == 4)
        #expect(result.maximumDisplayCount == 2)
        #expect(result.maximumEstimatedDecodedMemoryBytes == Int64(128 * 1_024 * 1_024))
        #expect(result.droppedFrames == 1)
    }

    @MainActor
    @Test func libraryImportsPersistsAndRemovesAnImage() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("NotchLandSceneTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Aurora.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let libraryRoot = root.appendingPathComponent("Library", isDirectory: true)
        let library = WallpaperSceneLibrary(rootDirectory: libraryRoot)
        let imported = try await library.importScene(from: source)

        #expect(imported.title == "Aurora")
        #expect(imported.kind == .image)
        #expect(imported.thumbnailFilename == nil)
        #expect(fileManager.fileExists(atPath: library.assetURL(for: imported).path))

        let rendering = WallpaperSceneRenderingConfiguration(
            scalingMode: .fit,
            playbackRate: 1.25,
            dimming: 0.32
        )
        try library.updateRendering(
            forSceneID: imported.id,
            configuration: rendering
        )

        library.toggleFavorite(imported)
        let collection = try #require(library.createCollection(named: "Calm"))
        library.toggle(imported, in: collection)
        #expect(library.isFavorite(imported))
        #expect(library.contains(imported, in: collection))

        let reloadedLibrary = WallpaperSceneLibrary(rootDirectory: libraryRoot)
        #expect(reloadedLibrary.scenes.map(\.id) == [imported.id])
        #expect(reloadedLibrary.scene(withID: imported.id)?.rendering == rendering)
        #expect(reloadedLibrary.isFavorite(imported))
        let reloadedCollection = try #require(
            reloadedLibrary.collections.first { $0.id == collection.id }
        )
        #expect(reloadedLibrary.contains(imported, in: reloadedCollection))

        try reloadedLibrary.remove(imported)
        #expect(reloadedLibrary.scenes.isEmpty)
        #expect(reloadedLibrary.scenes(in: reloadedLibrary.favorites).isEmpty)
        #expect(reloadedLibrary.scenes(in: reloadedCollection).isEmpty)
        #expect(!fileManager.fileExists(atPath: reloadedLibrary.assetURL(for: imported).path))
    }

    @MainActor
    @Test func scenePackageExportsImportsAndRejectsTampering() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("NotchLandPackageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("Desert.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02]).write(to: sourceURL)

        let sourceLibrary = WallpaperSceneLibrary(
            rootDirectory: root.appendingPathComponent("SourceLibrary", isDirectory: true)
        )
        let sourceScene = try await sourceLibrary.importScene(from: sourceURL)
        let rendering = WallpaperSceneRenderingConfiguration(
            scalingMode: .stretch,
            playbackRate: 0.75,
            dimming: 0.18,
            motionPreset: .slowDrift,
            saturation: 1.18,
            contrast: 1.08,
            vignette: 0.24,
            ambientEffect: .dust,
            effectIntensity: 0.7,
            parallaxStrength: 0.35,
            musicReaction: .ambientGlow,
            musicReactionIntensity: 0.65,
            composerLayers: [
                .init(
                    kind: .media,
                    scale: 1.08,
                    offsetX: 0.04,
                    blurRadius: 2,
                    maskStyle: .fadeTop,
                    maskFeather: 0.58,
                    animationPreset: .breathe,
                    animationAmount: 0.48,
                    animationDuration: 6
                ),
                .init(
                    kind: .atmosphere,
                    opacity: 0.68,
                    blendMode: .add,
                    offsetY: 0.07
                ),
                .init(kind: .musicGlow, blendMode: .screen),
                .init(kind: .vignette, opacity: 0.75, blendMode: .multiply),
                .init(kind: .dimming, blendMode: .multiply),
            ]
        )
        try sourceLibrary.updateRendering(
            forSceneID: sourceScene.id,
            configuration: rendering
        )
        let configuredSourceScene = try #require(sourceLibrary.scene(withID: sourceScene.id))
        let packageURL = root.appendingPathComponent("Desert.notchscene", isDirectory: true)
        try await sourceLibrary.exportPackage(configuredSourceScene, to: packageURL)

        let unexpectedURL = packageURL.appendingPathComponent("unexpected.bin")
        try Data([0x00]).write(to: unexpectedURL)
        let strictLibrary = WallpaperSceneLibrary(
            rootDirectory: root.appendingPathComponent("StrictLibrary", isDirectory: true)
        )
        do {
            _ = try await strictLibrary.importScene(from: packageURL)
            Issue.record("A package with extra files should not be imported")
        } catch let error as WallpaperScenePackageError {
            #expect(error == .invalidPackage)
        }
        try fileManager.removeItem(at: unexpectedURL)

        let destinationLibrary = WallpaperSceneLibrary(
            rootDirectory: root.appendingPathComponent("DestinationLibrary", isDirectory: true)
        )
        let importedScene = try await destinationLibrary.importScene(from: packageURL)
        #expect(importedScene.title == sourceScene.title)
        #expect(importedScene.author == sourceScene.author)
        #expect(importedScene.kind == sourceScene.kind)
        #expect(importedScene.rendering == rendering)

        let manifestURL = packageURL.appendingPathComponent(
            WallpaperScenePackageManifest.filename
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            WallpaperScenePackageManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        try Data([0x00, 0x01, 0x02]).write(
            to: packageURL.appendingPathComponent(manifest.assetFilename),
            options: .atomic
        )

        let tamperedLibrary = WallpaperSceneLibrary(
            rootDirectory: root.appendingPathComponent("TamperedLibrary", isDirectory: true)
        )
        do {
            _ = try await tamperedLibrary.importScene(from: packageURL)
            Issue.record("A modified package asset should not be imported")
        } catch let error as WallpaperScenePackageError {
            #expect(error == .checksumMismatch)
        }
    }
}
