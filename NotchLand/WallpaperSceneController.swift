//
//  WallpaperSceneController.swift
//  NotchLand
//
//  Coordinates the scene library, adaptive policy, and per-display renderers.
//

import AppKit
import Combine
import QuartzCore

@MainActor
final class WallpaperSceneController: ObservableObject {
    private enum Keys {
        static let activeSceneID = "scenes.activeSceneID"
        static let isPaused = "scenes.isPaused"
        static let automationConfiguration = "scenes.automationConfiguration.v1"
        static let displayPolicy = "scenes.displayPolicy.v1"
        static let selectedDisplayIDs = "scenes.selectedDisplayIDs.v1"
    }

    private enum SelectionOrigin {
        case manual
        case automation(WallpaperAutomationReason)
    }

    private enum Timing {
        static let crossfadeDuration: TimeInterval = 0.46
        static let automationPollingInterval: Duration = .seconds(30)
        static let manualOverrideDuration: TimeInterval = 2 * 60 * 60
        static let renderingPersistenceDelay: Duration = .milliseconds(280)
        static let videoVisibilityPollingInterval: Duration = .seconds(2)
        static let idleVisibilityPollingInterval: Duration = .seconds(8)
    }

    @Published private(set) var activeSceneID: UUID?
    @Published private(set) var isRunning = false
    @Published var isPaused: Bool {
        didSet {
            defaults.set(isPaused, forKey: Keys.isPaused)
            updatePlaybackState()
        }
    }
    @Published var errorMessage: String?
    @Published private(set) var isDropTargetVisible = false
    @Published private(set) var isHoveringDropZone = false
    @Published private(set) var isFullscreenApplicationActive = false
    @Published private(set) var isSessionActive = true
    @Published private(set) var libraryPresentationRevision = 0
    @Published private(set) var automationConfiguration: WallpaperAutomationConfiguration
    @Published private(set) var automationReason: WallpaperAutomationReason?
    @Published private(set) var manualOverrideUntil: Date?
    @Published private(set) var exportingSceneID: UUID?
    @Published private(set) var displayPolicy: NotchDisplayPolicy
    @Published private(set) var selectedDisplayIDs: Set<UInt32>
    @Published private(set) var mediaPlayback = WallpaperMediaPlaybackSnapshot.inactive

    let library: WallpaperSceneLibrary
    let performance: WallpaperPerformanceMonitor
    let telemetry: WallpaperTelemetryMonitor

    private let defaults: UserDefaults
    private let displayCoordinator: DisplayCoordinator
    private weak var focusMode: FocusModeController?
    private var windows: [CGDirectDisplayID: WallpaperSceneWindow] = [:]
    private var retiringWindows: [WallpaperSceneWindow] = []
    private var isStarted = false
    private var visibilityTask: Task<Void, Never>?
    private var automationTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var renderingPersistenceTask: Task<Void, Never>?
    private var transitionGeneration = UUID()
    private var crossfadeStartedGeneration: UUID?
    private var lastRotationDate = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []
    private var libraryCancellable: AnyCancellable?

    var activeScene: WallpaperScene? {
        library.scene(withID: activeSceneID)
    }

    var availableDisplays: [DisplaySnapshot] {
        displayCoordinator.displays
    }

    var targetDisplayIDs: Set<UInt32> {
        Set(
            DisplaySelectionResolver.selectedIDs(
                policy: displayPolicy,
                selectedIDs: selectedDisplayIDs,
                displays: availableDisplays
            )
        )
    }

    var isSuspendedBySystem: Bool {
        !isSessionActive || isFullscreenApplicationActive || performance.shouldSuspendVideo
    }

    var suspensionDetail: String? {
        if !isSessionActive { return "Paused while the screen is unavailable" }
        if performance.shouldSuspendVideo { return "Paused while your Mac cools down" }
        if isFullscreenApplicationActive { return "Paused behind a fullscreen app" }
        return nil
    }

    var isManualOverrideActive: Bool {
        guard let manualOverrideUntil else { return false }
        return manualOverrideUntil > .now
    }

    var automationStatusDetail: String {
        guard automationConfiguration.isEnabled else { return "Automation is off" }
        if let manualOverrideUntil, manualOverrideUntil > .now {
            return "Manual choice until \(manualOverrideUntil.formatted(date: .omitted, time: .shortened))"
        }
        if let automationReason { return automationReason.title }
        return "Watching Focus, power, time, and rotation"
    }

    var rotationSourceDetail: String {
        guard automationConfiguration.rotatesFavorites else { return "Rotation is disabled" }
        switch automationConfiguration.rotationSource {
        case .favorites:
            let count = library.scenes(in: library.favorites).count
            return count == 1 ? "1 favorite scene" : "\(count) favorite scenes"
        case .playlist:
            guard let playlist = selectedRotationPlaylist else { return "Choose a playlist" }
            let count = library.scenes(in: playlist).count
            return count == 1 ? "1 scene in \(playlist.title)" : "\(count) scenes in \(playlist.title)"
        }
    }

    var selectedRotationPlaylist: WallpaperSceneCollection? {
        guard let playlistID = automationConfiguration.rotationPlaylistID else { return nil }
        return library.collections.first { $0.id == playlistID && $0.kind == .custom }
    }

    init(
        library: WallpaperSceneLibrary,
        performance: WallpaperPerformanceMonitor,
        focusMode: FocusModeController? = nil,
        nowPlaying: NowPlayingService? = nil,
        displayCoordinator: DisplayCoordinator,
        telemetry: WallpaperTelemetryMonitor? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.performance = performance
        self.focusMode = focusMode
        self.displayCoordinator = displayCoordinator
        self.telemetry = telemetry ?? WallpaperTelemetryMonitor()
        self.defaults = defaults
        displayPolicy = defaults.string(forKey: Keys.displayPolicy)
            .flatMap(NotchDisplayPolicy.init(rawValue:)) ?? .allDisplays
        selectedDisplayIDs = Set(
            defaults.array(forKey: Keys.selectedDisplayIDs)?
                .compactMap { ($0 as? NSNumber)?.uint32Value } ?? []
        )
        activeSceneID = defaults.string(forKey: Keys.activeSceneID).flatMap(UUID.init(uuidString:))
        isPaused = defaults.bool(forKey: Keys.isPaused)
        if let data = defaults.data(forKey: Keys.automationConfiguration),
           let savedConfiguration = try? JSONDecoder().decode(
               WallpaperAutomationConfiguration.self,
               from: data
           ) {
            automationConfiguration = savedConfiguration
        } else {
            automationConfiguration = WallpaperAutomationConfiguration()
        }
        libraryCancellable = library.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }

        nowPlaying?.$track
            .map { track in
                guard let track else { return WallpaperMediaPlaybackSnapshot.inactive }
                let presentation = track.compactPresentation
                return WallpaperMediaPlaybackSnapshot(
                    isPlaying: presentation.isPlaying,
                    accentRed: presentation.accentColor.red,
                    accentGreen: presentation.accentColor.green,
                    accentBlue: presentation.accentColor.blue
                )
            }
            .removeDuplicates()
            .sink { [weak self] snapshot in
                self?.updateMediaPlayback(snapshot)
            }
            .store(in: &cancellables)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        performance.start()

        displayCoordinator.$revision
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.rebuildRenderers() }
            .store(in: &cancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .merge(with: workspaceCenter.publisher(for: NSWorkspace.screensDidSleepNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isSessionActive = false
                self?.updatePlaybackState()
            }
            .store(in: &cancellables)

        workspaceCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .merge(with: workspaceCenter.publisher(for: NSWorkspace.screensDidWakeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isSessionActive = true
                self?.updatePlaybackState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            performance.$selectedProfile,
            performance.$effectiveProfile,
            performance.$shouldSuspendVideo
        )
            .dropFirst()
            .sink { [weak self] _, _, _ in
                self?.updatePlaybackState()
            }
            .store(in: &cancellables)

        performance.$isLowPowerModeEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.evaluateAutomation(forceRotation: true)
            }
            .store(in: &cancellables)

        focusMode?.$isFocusActive
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.evaluateAutomation(forceRotation: true)
            }
            .store(in: &cancellables)

        if activeScene != nil {
            rebuildRenderers()
        } else {
            clearPersistedSelection()
        }
        startVisibilityMonitoring()
        startAutomationMonitoring()
        evaluateAutomation(forceRotation: true)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        performance.stop()
        visibilityTask?.cancel()
        visibilityTask = nil
        automationTask?.cancel()
        automationTask = nil
        transitionTask?.cancel()
        transitionTask = nil
        flushRenderingChanges()
        windows.values.forEach { $0.stopRendering() }
        retiringWindows.forEach { $0.stopRendering() }
        windows.removeAll()
        retiringWindows.removeAll()
        isRunning = false
        telemetry.deactivate()
        dragEnded()
    }

    func apply(_ scene: WallpaperScene) {
        apply(scene, origin: .manual)
    }

    func updateAutomationConfiguration(
        _ update: (inout WallpaperAutomationConfiguration) -> Void
    ) {
        var updated = automationConfiguration
        update(&updated)
        updated.rotationIntervalMinutes = Self.normalizedRotationInterval(
            updated.rotationIntervalMinutes
        )
        guard updated != automationConfiguration else { return }
        automationConfiguration = updated
        persistAutomationConfiguration()
        manualOverrideUntil = nil
        automationReason = nil
        lastRotationDate = .distantPast
        evaluateAutomation(forceRotation: true)
    }

    func resumeAutomationNow() {
        manualOverrideUntil = nil
        evaluateAutomation(forceRotation: true)
    }

    func setDisplayPolicy(_ policy: NotchDisplayPolicy) {
        guard displayPolicy != policy else { return }
        displayPolicy = policy
        defaults.set(policy.rawValue, forKey: Keys.displayPolicy)
        rebuildRenderers(crossfade: activeScene != nil)
    }

    func toggleTargetDisplay(_ displayID: UInt32) {
        if selectedDisplayIDs.contains(displayID) {
            selectedDisplayIDs.remove(displayID)
        } else {
            selectedDisplayIDs.insert(displayID)
        }
        defaults.set(selectedDisplayIDs.sorted().map(NSNumber.init(value:)), forKey: Keys.selectedDisplayIDs)
        guard displayPolicy == .selectedDisplays else { return }
        rebuildRenderers(crossfade: activeScene != nil)
    }

    private func apply(_ scene: WallpaperScene, origin: SelectionOrigin) {
        guard library.scene(withID: scene.id) != nil else {
            errorMessage = WallpaperSceneLibraryError.sceneNotFound.localizedDescription
            return
        }

        let shouldCrossfade = activeSceneID != nil && activeSceneID != scene.id
        activeSceneID = scene.id
        defaults.set(scene.id.uuidString, forKey: Keys.activeSceneID)
        isPaused = false
        errorMessage = nil
        switch origin {
        case .manual:
            automationReason = nil
            if automationConfiguration.isEnabled {
                manualOverrideUntil = Date().addingTimeInterval(Timing.manualOverrideDuration)
            }
        case .automation(let reason):
            automationReason = reason
            if reason.isRotation {
                lastRotationDate = .now
            }
        }
        rebuildRenderers(crossfade: shouldCrossfade)
    }

    func togglePaused() {
        guard activeScene != nil else { return }
        isPaused.toggle()
    }

    func requestOpenLibrary() {
        libraryPresentationRevision &+= 1
    }

    func dragApproached(urls: [URL]) {
        guard Self.isSceneDrop(urls) else {
            dragEnded()
            return
        }
        isDropTargetVisible = true
    }

    func setHoveringDropZone(_ isHovering: Bool) {
        guard isDropTargetVisible else { return }
        self.isHoveringDropZone = isHovering
    }

    func dragEnded() {
        isDropTargetVisible = false
        isHoveringDropZone = false
    }

    static func isSceneDrop(_ urls: [URL]) -> Bool {
        guard urls.count == 1, let url = urls.first else { return false }
        return WallpaperSceneFileSupport.isSupportedImport(url)
    }

    func deactivate() {
        transitionTask?.cancel()
        transitionTask = nil
        windows.values.forEach { $0.stopRendering() }
        retiringWindows.forEach { $0.stopRendering() }
        windows.removeAll()
        retiringWindows.removeAll()
        activeSceneID = nil
        isRunning = false
        telemetry.deactivate()
        automationReason = nil
        if automationConfiguration.isEnabled {
            manualOverrideUntil = Date().addingTimeInterval(Timing.manualOverrideDuration)
        }
        clearPersistedSelection()
    }

    func remove(_ scene: WallpaperScene) {
        let wasActive = scene.id == activeSceneID
        if wasActive { deactivate() }
        do {
            try library.remove(scene)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func importAndApply(from url: URL) async -> Bool {
        guard let scene = await importScene(from: url) else { return false }
        apply(scene)
        return true
    }

    func importScene(from url: URL) async -> WallpaperScene? {
        do {
            let scene = try await library.importScene(from: url)
            dragEnded()
            errorMessage = nil
            return scene
        } catch {
            errorMessage = error.localizedDescription
            dragEnded()
            return nil
        }
    }

    @discardableResult
    func export(_ scene: WallpaperScene, to destinationURL: URL) async -> Bool {
        guard exportingSceneID == nil else { return false }
        exportingSceneID = scene.id
        defer { exportingSceneID = nil }
        do {
            try await library.exportPackage(scene, to: destinationURL)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateRendering(
        for sceneID: UUID,
        configuration: WallpaperSceneRenderingConfiguration
    ) {
        do {
            let normalizedConfiguration = configuration.normalized
            try library.updateRendering(
                forSceneID: sceneID,
                configuration: normalizedConfiguration,
                persistsImmediately: false
            )
            errorMessage = nil
            if activeSceneID == sceneID, let scene = activeScene {
                let paused = shouldPause(scene: scene)
                windows.values.forEach {
                    $0.update(
                        profile: performance.effectiveProfile,
                        rendering: normalizedConfiguration,
                        paused: paused
                    )
                }
            }
            scheduleRenderingPersistence()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildRenderers(crossfade: Bool = false) {
        guard let scene = activeScene else {
            windows.values.forEach { $0.stopRendering() }
            isRunning = false
            telemetry.deactivate()
            return
        }

        let sceneChanged = telemetry.snapshot.sceneID != scene.id
        let screensByID = Dictionary(uniqueKeysWithValues: displayCoordinator
            .selectedScreens(policy: displayPolicy, selectedIDs: selectedDisplayIDs)
            .compactMap { screen in
                screen.displayID.map { ($0, screen) }
            })

        refreshTelemetryContext(scene: scene, displayIDs: Set(screensByID.keys))

        let shouldCrossfade = crossfade
            && !windows.isEmpty
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if shouldCrossfade {
            crossfadeToScene(scene, on: screensByID)
            return
        }

        let transitionID: UUID? = (sceneChanged || windows.isEmpty) ? UUID() : nil
        if let transitionID {
            let strategy: WallpaperTransitionStrategy = crossfade
                ? .reducedMotionSwap
                : .direct
            telemetry.beginTransition(
                id: transitionID,
                sceneID: scene.id,
                targetDisplayIDs: Set(screensByID.keys),
                strategy: strategy
            )
        }

        let staleDisplayIDs = windows.keys.filter { screensByID[$0] == nil }
        for displayID in staleDisplayIDs {
            windows.removeValue(forKey: displayID)?.stopRendering()
        }

        let assetURL = library.assetURL(for: scene)
        for (displayID, screen) in screensByID {
            let window = windows[displayID] ?? WallpaperSceneWindow(screen: screen)
            windows[displayID] = window
            window.setFrame(screen.frame, display: false)
            window.display(
                scene: scene,
                assetURL: assetURL,
                profile: performance.effectiveProfile,
                paused: shouldPause(scene: scene),
                onRendererEvent: { [weak self] rendererID, event in
                    self?.telemetry.rendererEvent(
                        event,
                        rendererID: rendererID,
                        displayID: displayID,
                        transitionID: transitionID
                    )
                }
            )
            window.update(mediaPlayback: mediaPlayback)
        }
        isRunning = !windows.isEmpty
        if let transitionID, windows.isEmpty {
            telemetry.cancelTransition(
                id: transitionID,
                reason: "No target display was available"
            )
        }
    }

    private func crossfadeToScene(
        _ scene: WallpaperScene,
        on screensByID: [CGDirectDisplayID: NSScreen]
    ) {
        if let activeTransition = telemetry.snapshot.currentTransition {
            telemetry.cancelTransition(
                id: activeTransition.id,
                reason: "Superseded by a newer scene"
            )
        }
        finishRetiringWindows()
        transitionGeneration = UUID()
        let generation = transitionGeneration
        crossfadeStartedGeneration = nil
        telemetry.beginTransition(
            id: generation,
            sceneID: scene.id,
            targetDisplayIDs: Set(screensByID.keys),
            strategy: .dualRendererCrossfade
        )

        let oldWindows = Array(windows.values)
        let assetURL = library.assetURL(for: scene)
        var nextWindows: [CGDirectDisplayID: WallpaperSceneWindow] = [:]
        var readyDisplayIDs = Set<CGDirectDisplayID>()

        for (displayID, screen) in screensByID {
            let window = WallpaperSceneWindow(screen: screen)
            window.alphaValue = 0
            nextWindows[displayID] = window
        }

        for (displayID, window) in nextWindows {
            window.display(
                scene: scene,
                assetURL: assetURL,
                profile: performance.effectiveProfile,
                paused: shouldPause(scene: scene),
                onReady: { [weak self, weak window] in
                    guard let self, let window,
                          self.transitionGeneration == generation,
                          self.windows[displayID] === window else { return }
                    readyDisplayIDs.insert(displayID)
                    guard readyDisplayIDs.count == nextWindows.count else { return }
                    self.beginCrossfade(
                        nextWindows: Array(nextWindows.values),
                        oldWindows: oldWindows,
                        generation: generation
                    )
                },
                onRendererEvent: { [weak self] rendererID, event in
                    self?.telemetry.rendererEvent(
                        event,
                        rendererID: rendererID,
                        displayID: displayID,
                        transitionID: generation
                    )
                }
            )
            window.update(mediaPlayback: mediaPlayback)
        }

        windows = nextWindows
        retiringWindows = oldWindows
        isRunning = !nextWindows.isEmpty

        // Still images decode off the main actor. The old wallpaper stays fully
        // visible until every display has a ready frame, avoiding the black flash
        // and stutter caused by animating an empty replacement window.
        if nextWindows.isEmpty {
            finishRetiringWindows()
            telemetry.cancelTransition(
                id: generation,
                reason: "No target display was available"
            )
        } else {
            transitionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(420))
                guard let self, !Task.isCancelled, self.transitionGeneration == generation else { return }
                self.beginCrossfade(
                    nextWindows: Array(nextWindows.values),
                    oldWindows: oldWindows,
                    generation: generation
                )
            }
        }
    }

    private func beginCrossfade(
        nextWindows: [WallpaperSceneWindow],
        oldWindows: [WallpaperSceneWindow],
        generation: UUID
    ) {
        guard transitionGeneration == generation,
              crossfadeStartedGeneration != generation else { return }
        crossfadeStartedGeneration = generation
        transitionTask?.cancel()
        transitionTask = nil
        MotionDebug.record(
            name: "wallpaper.crossfade",
            surface: "Wallpaper Runtime",
            duration: Timing.crossfadeDuration,
            state: "\(oldWindows.count) old → \(nextWindows.count) ready",
            reason: "A newly selected scene finished preparing on every target display."
        )
        telemetry.transitionAnimationStarted(id: generation)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Timing.crossfadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            nextWindows.forEach { $0.animator().alphaValue = 1 }
            oldWindows.forEach { $0.animator().alphaValue = 0 }
        }

        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Timing.crossfadeDuration + 0.08))
            guard let self, !Task.isCancelled else { return }
            guard self.transitionGeneration == generation else { return }
            self.finishRetiringWindows()
            self.telemetry.completeTransition(id: generation)
        }
    }

    private func finishRetiringWindows() {
        transitionTask?.cancel()
        transitionTask = nil
        retiringWindows.forEach { $0.stopRendering() }
        retiringWindows.removeAll()
    }

    private func updatePlaybackState() {
        guard let scene = activeScene else { return }
        let paused = shouldPause(scene: scene)
        refreshTelemetryContext(
            scene: scene,
            displayIDs: Set(displayCoordinator.displays.map(\.id))
        )
        telemetry.updatePlayback(
            isPaused: paused,
            reason: pauseReason(scene: scene)
        )
        windows.values.forEach {
            $0.update(
                profile: performance.effectiveProfile,
                rendering: scene.rendering,
                paused: paused
            )
        }
    }

    private func updateMediaPlayback(_ snapshot: WallpaperMediaPlaybackSnapshot) {
        mediaPlayback = snapshot
        windows.values.forEach { $0.update(mediaPlayback: snapshot) }
        retiringWindows.forEach { $0.update(mediaPlayback: snapshot) }
    }

    private func shouldPause(scene: WallpaperScene) -> Bool {
        isPaused || isSuspendedBySystem
    }

    private func pauseReason(scene: WallpaperScene) -> WallpaperPauseReason? {
        guard shouldPause(scene: scene) else { return nil }
        if isPaused { return .user }
        if !isSessionActive { return .sessionInactive }
        if performance.shouldSuspendVideo { return .thermalPressure }
        if isFullscreenApplicationActive { return .fullscreen }
        return nil
    }

    private func refreshTelemetryContext(
        scene: WallpaperScene,
        displayIDs: Set<UInt32>
    ) {
        let paused = shouldPause(scene: scene)
        telemetry.updateContext(
            scene: scene,
            assetURL: library.assetURL(for: scene),
            displayIDs: displayIDs,
            selectedProfile: performance.selectedProfile,
            effectiveProfile: performance.effectiveProfile,
            isLowPowerModeEnabled: performance.isLowPowerModeEnabled,
            thermalState: performance.thermalState,
            isPaused: paused,
            pauseReason: pauseReason(scene: scene)
        )
        for displayID in displayIDs {
            telemetry.updateVisibility(
                isFullscreenApplicationActive ? .fullscreenCovered : .visible,
                displayID: displayID
            )
        }
    }

    private func clearPersistedSelection() {
        defaults.removeObject(forKey: Keys.activeSceneID)
    }

    private func persistAutomationConfiguration() {
        guard let data = try? JSONEncoder().encode(automationConfiguration) else { return }
        defaults.set(data, forKey: Keys.automationConfiguration)
    }

    private func scheduleRenderingPersistence() {
        renderingPersistenceTask?.cancel()
        renderingPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Timing.renderingPersistenceDelay)
            guard let self, !Task.isCancelled else { return }
            do {
                try self.library.persistRenderingChanges()
                self.renderingPersistenceTask = nil
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func flushRenderingChanges() {
        guard renderingPersistenceTask != nil else { return }
        renderingPersistenceTask?.cancel()
        renderingPersistenceTask = nil
        do {
            try library.persistRenderingChanges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAutomationMonitoring() {
        automationTask?.cancel()
        automationTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: Timing.automationPollingInterval)
                guard !Task.isCancelled else { return }
                self.evaluateAutomation()
            }
        }
    }

    private func evaluateAutomation(forceRotation: Bool = false) {
        guard automationConfiguration.isEnabled, !library.scenes.isEmpty else {
            automationReason = nil
            return
        }

        if let manualOverrideUntil {
            if manualOverrideUntil > .now { return }
            self.manualOverrideUntil = nil
        }

        let period = WallpaperDayPeriod.current()
        if let match = WallpaperAutomationRuleResolver.firstMatch(
            configuration: automationConfiguration,
            availableSceneIDs: Set(library.scenes.map(\.id)),
            isFocusActive: focusMode?.isFocusActive == true,
            isLowPowerModeEnabled: performance.isLowPowerModeEnabled,
            dayPeriod: period
        ), let matchedScene = library.scene(withID: match.sceneID) {
            applyAutomationScene(matchedScene, reason: match.reason)
            return
        }

        guard automationConfiguration.rotatesFavorites else {
            automationReason = nil
            return
        }

        if performance.isLowPowerModeEnabled,
           automationConfiguration.pausesRotationOnLowPower {
            automationReason = nil
            return
        }

        let elapsed = Date().timeIntervalSince(lastRotationDate)
        let interval = TimeInterval(automationConfiguration.rotationIntervalMinutes * 60)
        guard forceRotation || elapsed >= interval else { return }
        let rotation = rotationCandidates()
        guard let nextScene = Self.nextScene(after: activeSceneID, in: rotation.scenes) else {
            automationReason = nil
            return
        }
        applyAutomationScene(nextScene, reason: rotation.reason)
    }

    private func applyAutomationScene(
        _ scene: WallpaperScene,
        reason: WallpaperAutomationReason
    ) {
        if activeSceneID == scene.id {
            automationReason = reason
            if reason.isRotation { lastRotationDate = .now }
            return
        }
        apply(scene, origin: .automation(reason))
    }

    private func rotationCandidates() -> (
        scenes: [WallpaperScene],
        reason: WallpaperAutomationReason
    ) {
        switch automationConfiguration.rotationSource {
        case .favorites:
            return (library.scenes(in: library.favorites), .favoriteRotation)
        case .playlist:
            guard let playlist = selectedRotationPlaylist else {
                return ([], .playlistRotation("Playlist"))
            }
            return (
                library.scenes(in: playlist),
                .playlistRotation(playlist.title)
            )
        }
    }

    nonisolated static func nextScene(
        after activeSceneID: UUID?,
        in scenes: [WallpaperScene]
    ) -> WallpaperScene? {
        guard !scenes.isEmpty else { return nil }
        guard let activeSceneID,
              let currentIndex = scenes.firstIndex(where: { $0.id == activeSceneID }) else {
            return scenes.first
        }
        return scenes[(currentIndex + 1) % scenes.count]
    }

    private static func normalizedRotationInterval(_ proposedValue: Int) -> Int {
        WallpaperAutomationConfiguration.supportedRotationIntervals.min {
            abs($0 - proposedValue) < abs($1 - proposedValue)
        } ?? WallpaperAutomationConfiguration.defaultRotationIntervalMinutes
    }

    private func startVisibilityMonitoring() {
        visibilityTask?.cancel()
        visibilityTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                guard self.activeScene?.kind == .video, self.isSessionActive else {
                    if self.isFullscreenApplicationActive {
                        self.isFullscreenApplicationActive = false
                        self.updatePlaybackState()
                    }
                    try? await Task.sleep(for: Timing.idleVisibilityPollingInterval)
                    continue
                }
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let displayFrames = self.displayCoordinator.displays.map(\.frame)
                let isFullscreen = await Task.detached(priority: .utility) {
                    WallpaperFullscreenDetector.isFullscreen(
                        frontmostPID: frontmostPID,
                        windows: WallpaperFullscreenDetector.currentWindowSnapshots(),
                        displayFrames: displayFrames
                    )
                }.value

                guard !Task.isCancelled else { return }
                if self.isFullscreenApplicationActive != isFullscreen {
                    self.isFullscreenApplicationActive = isFullscreen
                    self.updatePlaybackState()
                }
                try? await Task.sleep(for: Timing.videoVisibilityPollingInterval)
            }
        }
    }
}
