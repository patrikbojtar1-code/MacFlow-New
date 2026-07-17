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

    let library: WallpaperSceneLibrary
    let performance: WallpaperPerformanceMonitor

    private let defaults: UserDefaults
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
        return "Watching time of day and Focus"
    }

    init(
        library: WallpaperSceneLibrary,
        performance: WallpaperPerformanceMonitor,
        focusMode: FocusModeController? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.performance = performance
        self.focusMode = focusMode
        self.defaults = defaults
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
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        performance.start()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
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

        performance.$effectiveProfile
            .combineLatest(performance.$shouldSuspendVideo)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.updatePlaybackState()
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
            if reason == .favoriteRotation {
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
        do {
            let scene = try await library.importScene(from: url)
            apply(scene)
            dragEnded()
            return true
        } catch {
            errorMessage = error.localizedDescription
            dragEnded()
            return false
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
            try library.updateRendering(
                forSceneID: sceneID,
                configuration: configuration,
                persistsImmediately: false
            )
            errorMessage = nil
            if activeSceneID == sceneID, let scene = activeScene {
                let paused = shouldPause(scene: scene)
                windows.values.forEach {
                    $0.update(
                        profile: performance.effectiveProfile,
                        rendering: scene.rendering,
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
            return
        }

        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            screen.displayID.map { ($0, screen) }
        })

        let shouldCrossfade = crossfade
            && !windows.isEmpty
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if shouldCrossfade {
            crossfadeToScene(scene, on: screensByID)
            return
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
                paused: shouldPause(scene: scene)
            )
        }
        isRunning = !windows.isEmpty
    }

    private func crossfadeToScene(
        _ scene: WallpaperScene,
        on screensByID: [CGDirectDisplayID: NSScreen]
    ) {
        finishRetiringWindows()
        transitionGeneration = UUID()
        let generation = transitionGeneration
        crossfadeStartedGeneration = nil

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
                }
            )
        }

        windows = nextWindows
        retiringWindows = oldWindows
        isRunning = !nextWindows.isEmpty

        // Still images decode off the main actor. The old wallpaper stays fully
        // visible until every display has a ready frame, avoiding the black flash
        // and stutter caused by animating an empty replacement window.
        if nextWindows.isEmpty {
            finishRetiringWindows()
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
        windows.values.forEach {
            $0.update(
                profile: performance.effectiveProfile,
                rendering: scene.rendering,
                paused: paused
            )
        }
    }

    private func shouldPause(scene: WallpaperScene) -> Bool {
        isPaused || (scene.kind == .video && isSuspendedBySystem)
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

        if focusMode?.isFocusActive == true,
           let focusScene = library.scene(withID: automationConfiguration.focusSceneID) {
            applyAutomationScene(focusScene, reason: .focus)
            return
        }

        let period = WallpaperDayPeriod.current()
        if let scheduledScene = library.scene(
            withID: automationConfiguration.sceneID(for: period)
        ) {
            applyAutomationScene(scheduledScene, reason: .dayPeriod(period))
            return
        }

        guard automationConfiguration.rotatesFavorites else {
            automationReason = nil
            return
        }

        let elapsed = Date().timeIntervalSince(lastRotationDate)
        let interval = TimeInterval(automationConfiguration.rotationIntervalMinutes * 60)
        guard forceRotation || elapsed >= interval else { return }
        let favoriteScenes = library.scenes(in: library.favorites)
        guard let nextScene = Self.nextScene(after: activeSceneID, in: favoriteScenes) else {
            automationReason = nil
            return
        }
        applyAutomationScene(nextScene, reason: .favoriteRotation)
    }

    private func applyAutomationScene(
        _ scene: WallpaperScene,
        reason: WallpaperAutomationReason
    ) {
        if activeSceneID == scene.id {
            automationReason = reason
            if reason == .favoriteRotation { lastRotationDate = .now }
            return
        }
        apply(scene, origin: .automation(reason))
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
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let displayFrames = NSScreen.screens.map(\.frame)
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
                try? await Task.sleep(for: .seconds(1.25))
            }
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
