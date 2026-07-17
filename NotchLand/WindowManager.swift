//
//  WindowManager.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Owns the single floating NSPanel that hosts the notch UI. Reacts to changes
//  in NotchSettings (sizes, visibility) and AppState (expanded/collapsed) by
//  resizing/positioning/hiding the panel.
//
//  All window/AppKit concerns live here; SwiftUI rendering lives in FloatingNotchView.
//

import AppKit
import Combine
import ServiceManagement
import SwiftUI

private nonisolated struct ScrollGestureSample: Sendable {
    let normalizedDeltaX: CGFloat
    let normalizedDeltaY: CGFloat
    let mouseLocation: CGPoint
    let hasMomentum: Bool
    let didEndMomentum: Bool
    let didBegin: Bool
    let didEnd: Bool
    let isPrecise: Bool

    init(event: NSEvent, mouseLocation: CGPoint) {
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
        let inversion: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1

        normalizedDeltaX = event.scrollingDeltaX * multiplier * inversion
        normalizedDeltaY = event.scrollingDeltaY * multiplier * inversion
        self.mouseLocation = mouseLocation
        hasMomentum = !event.momentumPhase.isEmpty
        didEndMomentum = event.momentumPhase == .ended || event.momentumPhase == .cancelled
        didBegin = event.phase == .began || event.phase == .mayBegin
        didEnd = event.phase == .ended || event.phase == .cancelled
        isPrecise = event.hasPreciseScrollingDeltas
    }
}

@MainActor
final class WindowManager: NSObject {
    /// The panel is sized once to the *maximum* envelope across all states (Dynamic
    /// Island style) so state changes only animate the SwiftUI shape inside —
    /// no NSWindow resize, no NSHostingView constraint thrash, no overlapping
    /// NSAnimationContext animations to interrupt each other.
    /// Extra space around the visible notch so the SwiftUI shadow has room to render.
    static let shadowHorizontalPadding: CGFloat = 40
    static let shadowBottomPadding: CGFloat = 40

    private enum PanelLevel {
        static let interactive = NSWindow.Level.mainMenu + 3
        static let lockScreen = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
    }

    private let settings: NotchSettings
    private let displayCoordinator: DisplayCoordinator
    private let appState: AppState
    private let hud: HUDController
    private let nowPlaying: NowPlayingService
    private let batteryAlerts: BatteryAlertController
    private let focusMode: FocusModeController
    private let screenLock: ScreenLockController
    private let biometrics: BiometricAuthenticationController
    private let calendar: CalendarService
    private let eventCountdown: EventCountdownController
    private let airDrop: AirDropController
    private let fileShelf: FileShelfController
    private let quickNotes: QuickNotesController
    private let todo: TodoController
    private let clipboard: ClipboardController
    private let quickActions: QuickActionsController
    private let mirror: MirrorController
    private let widgetPreferences: WidgetPreferencesController
    private let wallet: WalletContributionController
    private let calls: CallActivityController
    private let systemCalls: SystemCallActivitySource
    private let liveActivities: LiveActivityController
    private let eventCenter: NotchEventCenter
    private let shortcutsBridge: ShortcutsBridgeController
    private let dropIntelligence: DropIntelligenceController
    private let notchTimer: NotchTimerController
    private let scenes: WallpaperSceneController
    private let mouseFree: MouseFreeController
    private let updater: UpdaterController

    private var notchPanels: [UInt32: NotchPanel] = [:]
    private var dragMonitors: [Any] = []
    private var cachedDragPasteboardChangeCount = -1
    private var cachedDraggedURLs: [URL] = []
    private var statusItem: NSStatusItem?
    private var companionWindow: NSWindow?
    private var hoverTimer: Timer?
    private var hoverEventMonitors: [Any] = []
    private var localScrollMonitor: Any?
    private var globalScrollMonitor: Any?
    private var scrollAccumulator = CGPoint.zero
    private var didTriggerScrollSwipe = false
    private var lastScrollSwipeAt = Date.distantPast
    private var pendingFrameUpdate: DispatchWorkItem?
    private var pendingOnboardingFrameShrink: DispatchWorkItem?
    private var isPointerInsideNotch = false
    private var cancellables: Set<AnyCancellable> = []

    private enum ScrollSwipeDirection {
        case up
        case down
        case previousWidget
        case nextWidget
    }

    init(
        settings: NotchSettings,
        displayCoordinator: DisplayCoordinator,
        appState: AppState,
        hud: HUDController,
        nowPlaying: NowPlayingService,
        batteryAlerts: BatteryAlertController,
        focusMode: FocusModeController,
        screenLock: ScreenLockController,
        biometrics: BiometricAuthenticationController,
        calendar: CalendarService,
        eventCountdown: EventCountdownController,
        airDrop: AirDropController,
        fileShelf: FileShelfController,
        quickNotes: QuickNotesController,
        todo: TodoController,
        clipboard: ClipboardController,
        quickActions: QuickActionsController,
        mirror: MirrorController,
        widgetPreferences: WidgetPreferencesController,
        wallet: WalletContributionController,
        calls: CallActivityController,
        systemCalls: SystemCallActivitySource,
        liveActivities: LiveActivityController,
        eventCenter: NotchEventCenter,
        shortcutsBridge: ShortcutsBridgeController,
        dropIntelligence: DropIntelligenceController,
        notchTimer: NotchTimerController,
        scenes: WallpaperSceneController,
        mouseFree: MouseFreeController,
        updater: UpdaterController
    ) {
        self.settings = settings
        self.displayCoordinator = displayCoordinator
        self.appState = appState
        self.hud = hud
        self.nowPlaying = nowPlaying
        self.batteryAlerts = batteryAlerts
        self.focusMode = focusMode
        self.screenLock = screenLock
        self.biometrics = biometrics
        self.calendar = calendar
        self.eventCountdown = eventCountdown
        self.airDrop = airDrop
        self.fileShelf = fileShelf
        self.quickNotes = quickNotes
        self.todo = todo
        self.clipboard = clipboard
        self.quickActions = quickActions
        self.mirror = mirror
        self.widgetPreferences = widgetPreferences
        self.wallet = wallet
        self.calls = calls
        self.systemCalls = systemCalls
        self.liveActivities = liveActivities
        self.eventCenter = eventCenter
        self.shortcutsBridge = shortcutsBridge
        self.dropIntelligence = dropIntelligence
        self.notchTimer = notchTimer
        self.scenes = scenes
        self.mouseFree = mouseFree
        self.updater = updater
        super.init()
    }

    deinit {
        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
        }
        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
        }
        for monitor in dragMonitors {
            NSEvent.removeMonitor(monitor)
        }
        for monitor in hoverEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        pendingOnboardingFrameShrink?.cancel()
        hoverTimer?.invalidate()
    }

    func start() {
        observeSettings()
        observeDisplays()
        observeScreenLock()
        applyVisibility()
        startHoverTracking()
        installScrollGestureMonitors()
        installDragMonitors()
        showStatusItem()
        if settings.hasCompletedOnboarding {
            showCompanionWindow()
        }
        // First launch: don't force-expand here. FloatingNotchView starts with
        // a locked glyph in the collapsed notch, springs it open, then expands
        // through the same Dynamic Island-style notch transition.
        applyLaunchAtLoginPreference()
    }

    // MARK: - Observation

    private func observeSettings() {
        settings.$showNotch
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyVisibility()
                    self?.refreshStatusMenu()
                }
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.applyLaunchAtLoginPreference() }
            }
            .store(in: &cancellables)

        settings.$fileShelfEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !isEnabled {
                        self.fileShelf.dragEnded()
                        self.fileShelf.dismiss()
                    }
                    self.refreshStatusMenu()
                }
            }
            .store(in: &cancellables)

        // Panel envelope only changes with user-configured sizes; state transitions
        // animate purely inside SwiftUI, leaving the panel frame untouched.
        Publishers.MergeMany(
            settings.$collapsedWidth.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$collapsedHeight.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$expandedWidth.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$expandedHeight.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$notchContentSize.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$virtualNotchEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$displayPolicy.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$selectedDisplayIDs.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$displayConfigurations.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            MainActor.assumeIsolated { self?.updateNotchFrame(animated: false) }
        }
        .store(in: &cancellables)

        appState.$isExpanded
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshStatusMenu() }
            }
            .store(in: &cancellables)

        fileShelf.$items
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshStatusMenu() }
            }
            .store(in: &cancellables)

        scenes.$libraryPresentationRevision
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    AppDefaults.store.set(
                        MacFlowSection.wallpaperEngine.rawValue,
                        forKey: "macflow.selectedSection"
                    )
                    self?.showCompanionWindow()
                }
            }
            .store(in: &cancellables)

        settings.$hasCompletedOnboarding
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] completed in
                MainActor.assumeIsolated {
                    if completed {
                        self?.scheduleOnboardingFrameShrink()
                        self?.showCompanionWindow()
                    } else {
                        self?.pendingOnboardingFrameShrink?.cancel()
                        self?.companionWindow?.orderOut(nil)
                        self?.eventCountdown.clearDetail()
                        self?.appState.resetToCollapsed()
                        self?.applyVisibility()
                        self?.updateNotchFrame(animated: false)
                        self?.orderNotchPanelsFront()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func observeScreenLock() {
        screenLock.$currentPresentation
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] presentation in
                MainActor.assumeIsolated {
                    if presentation != nil {
                        self?.pendingFrameUpdate?.cancel()
                        self?.eventCountdown.clearDetail()
                        self?.appState.resetToCollapsed()
                        self?.biometrics.lock()
                    }
                    self?.applyVisibility()
                    self?.applyPanelLockMode(presentation != nil)
                    if presentation != nil, self?.settings.showNotch == true {
                        self?.updateNotchFrame(animated: false)
                        self?.orderNotchPanelsFront()
                    }
                }
            }
            .store(in: &cancellables)

        screenLock.$lifecycleRevision
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self,
                          self.settings.showNotch,
                          self.screenLock.currentPresentation != nil else { return }
                    self.applyVisibility()
                    self.applyPanelLockMode(true)
                    self.updateNotchFrame(animated: false)
                    self.notchPanels.values.forEach { $0.contentView?.needsDisplay = true }
                    self.orderNotchPanelsFront()
                }
            }
            .store(in: &cancellables)
    }

    private func observeDisplays() {
        displayCoordinator.$revision
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateNotchFrame(animated: false) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Show / Hide

    private func applyVisibility() {
        if settings.showNotch {
            showNotchPanel()
        } else {
            hideNotchPanel()
        }
    }

    private func showNotchPanel() {
        updateNotchFrame(animated: false)
        orderNotchPanelsFront()
    }

    private func hideNotchPanel() {
        appState.resetToCollapsed()
        notchPanels.values.forEach { $0.orderOut(nil) }
        updatePointerInsideState(false)
    }

    private func orderNotchPanelsFront() {
        notchPanels.values.forEach { $0.orderFrontRegardless() }
    }

    // MARK: - Hover tracking

    private func startHoverTracking() {
        guard hoverEventMonitors.isEmpty else { return }

        let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: eventMask,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.refreshHoverState() }
                return event
            }
        ) {
            hoverEventMonitors.append(localMonitor)
        }
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask,
            handler: { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.refreshHoverState() }
                }
            }
        ) {
            hoverEventMonitors.append(globalMonitor)
        }

        // A low-frequency fallback covers a stationary pointer while the shell
        // changes beneath it. Normal pointer movement is entirely event-driven.
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshHoverState()
            }
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshHoverState()
    }

    private func refreshHoverState() {
        let mouseLocation = NSEvent.mouseLocation
        let hitPadding: CGFloat = isPointerInsideNotch ? 18 : 10
        guard settings.showNotch,
              let panel = visiblePanel(containing: mouseLocation, padding: hitPadding) else {
            updatePointerInsideState(false)
            return
        }

        // Use a larger exit frame than entry frame. Without hysteresis the
        // animated shell can move its own hit boundary under the pointer and
        // repeatedly enter/exit while it is widening.
        let hoverFrame = interactiveNotchFrame(in: panel)
            .insetBy(dx: -hitPadding, dy: -hitPadding)
        updatePointerInsideState(hoverFrame.contains(mouseLocation), activePanel: panel)
    }

    private func updatePointerInsideState(_ isInside: Bool, activePanel: NotchPanel? = nil) {
        // The panel covers a large transparent envelope,
        // so we make it ignore mouse events anywhere outside the notch shape so
        // clicks fall through to whatever app sits below. While a file drag
        // hovers the drop zone the panel must keep receiving events so the
        // NSDraggingDestination can accept the drop.
        for panel in notchPanels.values {
            let isActivePanel = activePanel.map { $0 === panel } ?? false
            panel.ignoresMouseEvents = !(isInside && isActivePanel) && !fileShelf.isDropTargetVisible
        }

        // While the HUD is showing, don't propagate hover state to AppState —
        // volume/brightness key bursts shouldn't trigger a hover-to-expand,
        // which would replace the HUD with the expanded panel.
        let effectiveInside = isInside
            && hud.current == nil
            && batteryAlerts.currentPresentation == nil
            && focusMode.currentPresentation == nil
            && screenLock.currentPresentation == nil
            && calls.current == nil
            && liveActivities.current == nil
            && !fileShelf.isDropTargetVisible
            && settings.hasCompletedOnboarding

        let activeDisplayID = activePanel.flatMap(displayID(for:))
        let displayChanged = effectiveInside && appState.activeDisplayID != activeDisplayID
        guard isPointerInsideNotch != effectiveInside || displayChanged else { return }

        if effectiveInside {
            // Media uses the same sustained-hover expansion as every other
            // compact activity. Previously this was explicitly disabled while
            // a track existed, leaving the most common notch state inert.
            if displayChanged, isPointerInsideNotch {
                appState.mouseExited()
            }
            appState.mouseEntered(displayID: activeDisplayID)
        } else {
            appState.mouseExited()
        }
        isPointerInsideNotch = effectiveInside
    }

    // MARK: - AirDrop drag detection

    private func installDragMonitors() {
        guard dragMonitors.isEmpty else { return }
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.handleGlobalDragMoved() }
            }
        }) {
            dragMonitors.append(moved)
        }
        if let ended = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.handleGlobalDragEnded() }
            }
        }) {
            dragMonitors.append(ended)
        }
    }

    /// How far beyond the actual visible notch shape a drag still counts as
    /// "near" it — generous enough for a dragged Finder icon (coarser than a
    /// bare cursor) but nowhere near the whole screen.
    private static let dragProximityInset: CGFloat = -60

    private func handleGlobalDragMoved() {
        guard settings.showNotch else { return }
        guard let panel = visiblePanel(
            containing: NSEvent.mouseLocation,
            padding: abs(Self.dragProximityInset)
        ) else {
            if fileShelf.isDropTargetVisible || scenes.isDropTargetVisible {
                fileShelf.dragEnded()
                scenes.dragEnded()
                notchPanels.values.forEach { $0.ignoresMouseEvents = true }
            }
            return
        }
        // Proximity zone: a modest halo around the actual visible notch shape,
        // not the whole (much larger) panel envelope.
        let zone = interactiveNotchFrame(in: panel).insetBy(
            dx: Self.dragProximityInset,
            dy: Self.dragProximityInset
        )
        let urls = draggedFileURLs()
        guard zone.contains(NSEvent.mouseLocation), !urls.isEmpty else {
            if fileShelf.isDropTargetVisible || scenes.isDropTargetVisible {
                fileShelf.dragEnded()
                scenes.dragEnded()
                panel.ignoresMouseEvents = true
            }
            return
        }

        if WallpaperSceneController.isSceneDrop(urls) {
            fileShelf.dragEnded()
            scenes.dragApproached(urls: urls)
        } else if settings.fileShelfEnabled {
            scenes.dragEnded()
            fileShelf.dragApproached()
        } else {
            fileShelf.dragEnded()
            scenes.dragEnded()
            panel.ignoresMouseEvents = true
            return
        }
        panel.ignoresMouseEvents = false   // so the panel can receive the drop
    }

    private func draggedFileURLs() -> [URL] {
        let pasteboard = NSPasteboard(name: .drag)
        if pasteboard.changeCount == cachedDragPasteboardChangeCount {
            return cachedDraggedURLs
        }
        cachedDragPasteboardChangeCount = pasteboard.changeCount
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            cachedDraggedURLs = []
            return []
        }
        // Hover classification must never synchronously touch cloud storage.
        // Existence, metadata and bookmark validation happen after drop in
        // `FileShelfIO.prepare` on a detached task.
        cachedDraggedURLs = urls.map(\.standardizedFileURL)
        return cachedDraggedURLs
    }

    private func handleGlobalDragEnded() {
        cachedDragPasteboardChangeCount = -1
        cachedDraggedURLs = []
        guard fileShelf.isDropTargetVisible || scenes.isDropTargetVisible else { return }
        // Give the NSDraggingDestination a beat to process a drop landing on
        // the panel before the branch retracts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.fileShelf.isDropTargetVisible || self.scenes.isDropTargetVisible else { return }
                self.fileShelf.dragEnded()
                self.scenes.dragEnded()
                self.notchPanels.values.forEach { $0.ignoresMouseEvents = true }
            }
        }
    }

    private func installScrollGestureMonitors() {
        guard localScrollMonitor == nil, globalScrollMonitor == nil else { return }

        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let sample = ScrollGestureSample(event: event, mouseLocation: NSEvent.mouseLocation)
            let didHandle = MainActor.assumeIsolated {
                self?.handleScrollGesture(sample) ?? false
            }
            return didHandle ? nil : event
        }

        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let sample = ScrollGestureSample(event: event, mouseLocation: NSEvent.mouseLocation)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    _ = self?.handleScrollGesture(sample)
                }
            }
        }
    }

    private func handleScrollGesture(_ sample: ScrollGestureSample) -> Bool {
        guard settings.showNotch,
              let panel = visiblePanel(containing: sample.mouseLocation, padding: 10) else {
            resetScrollGesture()
            return false
        }

        let gestureFrame = interactiveNotchFrame(in: panel).insetBy(dx: -10, dy: -10)
        guard gestureFrame.contains(sample.mouseLocation) else {
            resetScrollGesture()
            return false
        }

        if shouldLetExpandedCalendarHandleScroll(
            in: gestureFrame,
            mouseLocation: sample.mouseLocation
        ) {
            resetScrollGesture()
            return false
        }

        guard !sample.hasMomentum else {
            if sample.didEndMomentum {
                resetScrollGesture()
            }
            return false
        }

        if sample.didBegin {
            resetScrollGesture()
        }

        scrollAccumulator.x += sample.normalizedDeltaX
        scrollAccumulator.y += sample.normalizedDeltaY

        let didHandle: Bool
        if !didTriggerScrollSwipe,
           canTriggerScrollSwipe,
           sample.isPrecise,
           appState.isExpanded,
           isHorizontalScrollSwipe(scrollAccumulator) {
            didTriggerScrollSwipe = true
            lastScrollSwipeAt = Date()
            NotchHaptics.perform(.navigation)
            handleTrackpadSwipe(scrollAccumulator.x < 0 ? .nextWidget : .previousWidget)
            didHandle = true
        } else if !didTriggerScrollSwipe, canTriggerScrollSwipe, isVerticalScrollSwipe(scrollAccumulator) {
            didTriggerScrollSwipe = true
            lastScrollSwipeAt = Date()
            NotchHaptics.perform(.navigation)
            handleTrackpadSwipe(scrollAccumulator.y < 0 ? .down : .up)
            didHandle = true
        } else {
            didHandle = false
        }

        if sample.didEnd {
            resetScrollGesture()
        }

        return didHandle
    }

    private var canTriggerScrollSwipe: Bool {
        Date().timeIntervalSince(lastScrollSwipeAt) > 0.45
    }

    private func isVerticalScrollSwipe(_ delta: CGPoint) -> Bool {
        let verticalDistance = abs(delta.y)
        let horizontalDistance = abs(delta.x)
        return verticalDistance >= 26 && verticalDistance > horizontalDistance * 1.2
    }

    private func isHorizontalScrollSwipe(_ delta: CGPoint) -> Bool {
        let horizontalDistance = abs(delta.x)
        let verticalDistance = abs(delta.y)
        return horizontalDistance >= 34 && horizontalDistance > verticalDistance * 1.25
    }

    private func shouldLetExpandedCalendarHandleScroll(
        in gestureFrame: NSRect,
        mouseLocation: CGPoint
    ) -> Bool {
        guard settings.hasCompletedOnboarding,
              appState.isExpanded,
              nowPlaying.track == nil,
              !eventCountdown.isDetailPresented,
              batteryAlerts.currentPresentation == nil,
              focusMode.currentPresentation == nil,
              calls.current == nil,
              hud.current == nil else {
            return false
        }

        let bodyWidth = max(CGFloat(settings.expandedWidth), CalendarNotchMetrics.expandedSize.width)
        let bodyLeft = gestureFrame.midX - bodyWidth / 2
        let agendaLeft = bodyLeft
            + 18 // CalendarNotchView horizontal padding
            + CalendarNotchMetrics.monthColumnWidth
            + 16 // HStack spacing between month and agenda

        return mouseLocation.x >= agendaLeft - 6
    }

    private func handleTrackpadSwipe(_ direction: ScrollSwipeDirection) {
        switch direction {
        case .up:
            handleTrackpadSwipeUp()
        case .down:
            handleTrackpadSwipeDown()
        case .previousWidget:
            cycleExpandedWidget(by: -1)
        case .nextWidget:
            cycleExpandedWidget(by: 1)
        }
    }

    private func cycleExpandedWidget(by offset: Int) {
        guard appState.isExpanded else { return }
        let sequence: [NotchWidget] = [.media, .calendar, .files, .clipboard, .shortcuts]
        let stored = widgetPreferences.selectedWidget
        let currentIndex = sequence.firstIndex(of: stored) ?? 0
        var nextIndex = (currentIndex + offset) % sequence.count
        if nextIndex < 0 { nextIndex += sequence.count }
        var next = sequence[nextIndex]
        if next == .media, nowPlaying.track == nil {
            nextIndex = (nextIndex + offset) % sequence.count
            if nextIndex < 0 { nextIndex += sequence.count }
            next = sequence[nextIndex]
        }
        widgetPreferences.setMode(.pinned, for: next)
        appState.requestOpenWidget(rawValue: next.rawValue)
    }

    private func handleTrackpadSwipeDown() {
        guard batteryAlerts.currentPresentation == nil,
              focusMode.currentPresentation == nil,
              screenLock.currentPresentation == nil,
              calls.current == nil,
              hud.current == nil,
              !appState.isExpanded else {
            return
        }

        if eventCountdown.presentation != nil, eventCountdown.trackedEvent != nil {
            eventCountdown.showDetail()
        }
        appState.expand()
    }

    private func handleTrackpadSwipeUp() {
        if batteryAlerts.currentPresentation != nil {
            batteryAlerts.dismissCurrentPresentation()
            return
        }

        if focusMode.currentPresentation != nil {
            focusMode.dismissCurrentPresentation()
            return
        }

        if calls.current != nil {
            calls.dismiss()
            return
        }

        if hud.current != nil {
            hud.dismissCurrent()
            return
        }

        guard appState.isExpanded else { return }
        eventCountdown.clearDetail()
        appState.collapse()
    }

    private func resetScrollGesture() {
        scrollAccumulator = .zero
        didTriggerScrollSwipe = false
    }

    private func interactiveNotchFrame(in panel: NSPanel) -> NSRect {
        // Notch is centered horizontally at the panel's top edge. With a constant
        // panel envelope we can't derive its rect from the panel frame; we have to
        // compute the visible size from current state.
        let visible = currentVisibleSize(for: panel)
        let panelFrame = panel.frame
        return NSRect(
            x: panelFrame.midX - visible.width / 2,
            y: panelFrame.maxY - visible.height,
            width: visible.width,
            height: visible.height
        )
    }

    // MARK: - Menu bar companion

    private func showStatusItem() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                if let source = NSImage(named: "MacFlowBrandIcon"),
                   let image = source.copy() as? NSImage {
                    image.size = NSSize(width: 18, height: 18)
                    image.isTemplate = false
                    button.image = image
                } else {
                    button.image = MacFlowMenuBarSymbol.image()
                }
                button.imagePosition = .imageOnly
                button.toolTip = "MacFlow"
            }
            item.menu = NSMenu()
            statusItem = item
        }
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "MacFlow", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        if let source = NSImage(named: "MacFlowBrandIcon"),
           let image = source.copy() as? NSImage {
            image.size = NSSize(width: 18, height: 18)
            titleItem.image = image
        }
        menu.addItem(titleItem)
        menu.addItem(.separator())

        menu.addItem(makeMenuItem(
            title: "Open MacFlow",
            action: #selector(openCompanionWindow),
            key: "",
            systemImage: "macwindow"
        ))

        let showItem = makeMenuItem(
            title: "Show Notch",
            action: #selector(toggleNotch),
            key: "n",
            systemImage: "macbook"
        )
        showItem.state = settings.showNotch ? .on : .off
        menu.addItem(showItem)

        if settings.fileShelfEnabled {
            let shelfTitle = fileShelf.items.isEmpty
                ? "File Shelf"
                : "File Shelf (\(fileShelf.items.count))"
            let shelfItem = makeMenuItem(
                title: shelfTitle,
                action: #selector(openFileShelf),
                key: "f",
                systemImage: "folder"
            )
            shelfItem.isEnabled = settings.showNotch
            menu.addItem(shelfItem)
        }

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Quit MacFlow", action: #selector(quit), key: "q"))
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        key: String,
        systemImage: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        }
        return item
    }

    @objc private func toggleNotch() {
        settings.showNotch.toggle()
        refreshStatusMenu()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func toggleExpansion() {
        appState.toggle()
        refreshStatusMenu()
    }

    @objc private func openCompanionWindow() {
        showCompanionWindow()
    }

    @objc private func openFileShelf() {
        fileShelf.isPresented = true
        appState.expand()
        refreshStatusMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - System integration

    private func applyLaunchAtLoginPreference() {
        do {
            if settings.launchAtLogin {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("NotchLand failed to update launch-at-login: \(error.localizedDescription)")
        }
    }

    // MARK: - Companion window

    private func showCompanionWindow() {
        if companionWindow == nil {
            companionWindow = makeCompanionWindow()
        }

        guard let companionWindow else { return }
        let wasVisible = companionWindow.isVisible
        if !wasVisible { companionWindow.center() }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !wasVisible, !reduceMotion {
            companionWindow.alphaValue = 0
        }
        companionWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard !wasVisible, !reduceMotion else { return }

        if let layer = companionWindow.contentView?.layer {
            let translation = CABasicAnimation(keyPath: "transform.translation.y")
            translation.fromValue = -8
            translation.toValue = 0
            translation.duration = AppMotion.Duration.standard
            translation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(translation, forKey: "macflow.window.entry")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppMotion.Duration.standard
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            companionWindow.animator().alphaValue = 1
        }
    }

    private func makeCompanionWindow() -> NSWindow {
        let hosting = NSHostingView(
            rootView: SettingsView()
                .environmentObject(settings)
                .environmentObject(displayCoordinator)
                .environmentObject(appState)
                .environmentObject(hud)
                .environmentObject(batteryAlerts)
                .environmentObject(focusMode)
                .environmentObject(screenLock)
                .environmentObject(biometrics)
                .environmentObject(calendar)
                .environmentObject(eventCountdown)
                .environmentObject(airDrop)
                .environmentObject(fileShelf)
                .environmentObject(quickNotes)
                .environmentObject(todo)
                .environmentObject(clipboard)
                .environmentObject(quickActions)
                .environmentObject(mirror)
                .environmentObject(widgetPreferences)
                .environmentObject(wallet)
                .environmentObject(calls)
                .environmentObject(systemCalls)
                .environmentObject(liveActivities)
                .environmentObject(eventCenter)
                .environmentObject(shortcutsBridge)
                .environmentObject(dropIntelligence)
                .environmentObject(notchTimer)
                .environmentObject(scenes)
                .environmentObject(mouseFree)
                .environmentObject(updater)
        )
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: MacFlowMetrics.idealWindowWidth,
                height: MacFlowMetrics.idealWindowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacFlow"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        // MacFlow owns this companion window and centers it explicitly. Opting
        // out of AppKit state restoration prevents WindowScene from replaying
        // a server-side frame while the SwiftUI hierarchy is mid-layout.
        window.isRestorable = false
        window.contentMinSize = NSSize(
            width: MacFlowMetrics.minimumWindowWidth,
            height: MacFlowMetrics.minimumWindowHeight
        )
        // Keep a neutral AppKit container as the window's direct content view.
        // AppKit observes that view's frame to synchronize WindowScene state;
        // using NSHostingView directly creates a feedback loop when SwiftUI
        // updates its own layout during a server-driven window-frame restore.
        let container = NSView(frame: window.contentLayoutRect)
        container.wantsLayer = true
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
        hosting.wantsLayer = true
        window.isReleasedWhenClosed = false
        return window
    }

    // MARK: - Panel construction

    private func makePanel(displayID: UInt32) -> NotchPanel {
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // shadow drawn by SwiftUI so intensity is configurable
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        // The envelope panel covers a large transparent area; ignore mouse events
        // by default so clicks pass through, and only re-enable when the hover
        // poll confirms the cursor is inside the visible notch shape.
        panel.ignoresMouseEvents = true
        panel.level = panelLevel(forScreenLockPresentation: screenLock.currentPresentation)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.canBecomeVisibleWithoutLogin = true
        // Keep the notch visible in screenshots, screen recordings and video
        // calls. `.none` asks WindowServer to redact the whole panel.
        panel.sharingType = .readOnly

        let hosting = NotchHostingView(
            rootView: FloatingNotchView(displayID: displayID)
                .environmentObject(settings)
                .environmentObject(appState)
                .environmentObject(hud)
                .environmentObject(nowPlaying)
                .environmentObject(batteryAlerts)
                .environmentObject(focusMode)
                .environmentObject(screenLock)
                .environmentObject(biometrics)
                .environmentObject(calendar)
                .environmentObject(eventCountdown)
                .environmentObject(airDrop)
                .environmentObject(fileShelf)
                .environmentObject(quickNotes)
                .environmentObject(todo)
                .environmentObject(clipboard)
                .environmentObject(quickActions)
                .environmentObject(mirror)
                .environmentObject(widgetPreferences)
                .environmentObject(wallet)
                .environmentObject(calls)
                .environmentObject(liveActivities)
                .environmentObject(eventCenter)
                .environmentObject(shortcutsBridge)
                .environmentObject(dropIntelligence)
                .environmentObject(notchTimer)
                .environmentObject(scenes)
        )
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layerContentsRedrawPolicy = .onSetNeedsDisplay
        hosting.fileShelf = fileShelf
        hosting.appState = appState
        hosting.dropIntelligence = dropIntelligence
        hosting.scenes = scenes
        hosting.registerForDraggedTypes([.fileURL])
        panel.contentView = hosting
        applyBackingScale(to: panel)
        SkyLightWindowBridge.shared.delegateWindow(
            panel,
            to: screenLock.currentPresentation == nil ? .notchSurface : .lockScreenNotchOverlay
        )
        return panel
    }

    private func panelLevel(forScreenLockPresentation presentation: ScreenLockController.Presentation?) -> NSWindow.Level {
        presentation == nil ? PanelLevel.interactive : PanelLevel.lockScreen
    }

    private func applyPanelLockMode(_ isLockedOrUnlocking: Bool) {
        for panel in notchPanels.values {
            panel.level = isLockedOrUnlocking ? PanelLevel.lockScreen : PanelLevel.interactive
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .fullScreenAuxiliary,
                .ignoresCycle,
            ]
            SkyLightWindowBridge.shared.delegateWindow(
                panel,
                to: isLockedOrUnlocking ? .lockScreenNotchOverlay : .notchSurface
            )
        }
    }

    private func applyBackingScale(to panel: NSPanel) {
        let scale = panel.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
        panel.contentView?.layer?.contentsScale = scale
        applyScaleRecursively(panel.contentView, scale: scale)
    }

    private func applyScaleRecursively(_ view: NSView?, scale: CGFloat) {
        guard let view else { return }
        view.layer?.contentsScale = scale
        for sub in view.subviews { applyScaleRecursively(sub, scale: scale) }
    }

    // MARK: - Frame

    /// Sets the panel to the maximum envelope across all states. The panel never
    /// resizes for state transitions — only when settings or screen change. This
    /// is the single source of "no panel-resize during animation" guarantees.
    private func updateNotchFrame(animated: Bool) {
        _ = animated  // kept for source compatibility; envelope resize is never animated.
        let targetScreens = targetNotchScreens()
        let targetIDs = Set(targetScreens.compactMap(\.displayID))
        for staleID in Array(notchPanels.keys) where !targetIDs.contains(staleID) {
            notchPanels.removeValue(forKey: staleID)?.orderOut(nil)
        }
        let envelope = panelEnvelopeSize()
        let panelWidth = envelope.width + Self.shadowHorizontalPadding * 2
        let panelHeight = envelope.height + Self.shadowBottomPadding
        for screen in targetScreens {
            guard let displayID = screen.displayID else { continue }
            let panel = notchPanels[displayID] ?? makePanel(displayID: displayID)
            notchPanels[displayID] = panel
            let screenFrame = screen.frame
            let originX = screenFrame.midX - panelWidth / 2
                + settings.horizontalOffset(for: displayID)
            let originY = screenFrame.maxY - panelHeight
            let newFrame = NSRect(
                x: originX,
                y: originY,
                width: panelWidth,
                height: panelHeight
            )
            panel.setFrame(newFrame, display: true)
            applyBackingScale(to: panel)
            if settings.showNotch {
                panel.orderFrontRegardless()
            }
        }
    }

    /// The widest/tallest the visible notch can ever be across collapsed, peek,
    /// HUD, now-playing, and expanded states. Reserves the *largest possible*
    /// `invertedCornerRadius * 2` (the expanded value) so every state fits
    /// within a constant panel envelope.
    private func panelEnvelopeSize() -> CGSize {
        let baseWidth = CGFloat(settings.collapsedWidth)
        let baseHeight = CGFloat(settings.collapsedHeight)

        let extra = FloatingNotchView.expandedInvertedRadius * 2

        // Onboarding contributes to the envelope only when it could be shown —
        // once the user has tapped GET STARTED, the envelope shrinks back to
        // the regular feature footprint on the next frame update.
        let onboardingWidth: CGFloat = settings.hasCompletedOnboarding
            ? 0
            : max(OnboardingMetrics.expandedStepSize.width, OnboardingLockNotchMetrics.bodyWidth)
        let onboardingHeight: CGFloat = settings.hasCompletedOnboarding
            ? 0
            : max(OnboardingMetrics.expandedStepSize.height, OnboardingLockNotchMetrics.height)

        let expandedWidth = max(
            CGFloat(settings.expandedWidth),
            NowPlayingMetrics.expandedSize.width,
            CalendarNotchMetrics.expandedSize.width,
            EventDetailMetrics.eventOnlySize.width,
            FileShelfMetrics.expandedSize.width,
            NotchWidgetMetrics.expandedSize.width,
            NotchLayoutMetrics.bodySize(for: .large).width,
            onboardingWidth
        )
        let expandedHeight = max(
            CGFloat(settings.expandedHeight),
            NowPlayingMetrics.expandedSize.height,
            CalendarNotchMetrics.expandedSize.height,
            EventDetailMetrics.eventOnlySize.height,
            FileShelfMetrics.expandedSize.height,
            NotchWidgetMetrics.expandedSize.height,
            NotchLayoutMetrics.bodySize(for: .large).height,
            onboardingHeight
        )

        let collapsedFamilyWidth = max(
            baseWidth,
            HUDController.drawerMinWidth,
            NowPlayingMetrics.collapsedWidth,
            EventCountdownChipMetrics.musicComboContainerBodyWidth(baseWidth: baseWidth),
            EventCountdownChipMetrics.eventOnlyContainerBodyWidth(baseWidth: baseWidth),
            BatteryAlertMetrics.maxWidth,
            FocusModeAlertMetrics.maxWidth,
            LockScreenAlertMetrics.maxWidth,
            CallOverlayMetrics.mediumSize.width,
            LiveActivityChipMetrics.mediumSize.width,
            ImportantEventReminderMetrics.size(for: .medium).width
        )
        let collapsedFamilyHeight = max(
            baseHeight + max(
                HUDController.drawerHeight,
                NowPlayingMetrics.collapsedExtraHeight,
                NowPlayingMetrics.hoverExtraHeight,
                10 // bare hover-peek extra height
            ),
            BatteryAlertMetrics.maxHeight,
            FocusModeAlertMetrics.maxHeight,
            LockScreenAlertMetrics.maxHeight,
            CallOverlayMetrics.mediumSize.height,
            LiveActivityChipMetrics.mediumSize.height,
            ImportantEventReminderMetrics.size(for: .medium).height
        )

        return CGSize(
            width: max(expandedWidth, collapsedFamilyWidth) + extra,
            height: max(expandedHeight, collapsedFamilyHeight)
        )
    }

    private func scheduleNotchFrameUpdate(animated: Bool) {
        pendingFrameUpdate?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingFrameUpdate = nil
                self?.updateNotchFrame(animated: animated)
            }
        }
        pendingFrameUpdate = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleOnboardingFrameShrink() {
        pendingOnboardingFrameShrink?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingOnboardingFrameShrink = nil
                self?.updateNotchFrame(animated: false)
            }
        }
        pendingOnboardingFrameShrink = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
    }

    private func targetNotchScreens() -> [NSScreen] {
        displayCoordinator.selectedScreens(
            policy: settings.displayPolicy,
            selectedIDs: settings.selectedDisplayIDs
        )
        .filter { screen in
            settings.virtualNotchEnabled
                || screen.auxiliaryTopLeftArea != nil
                || screen.auxiliaryTopRightArea != nil
        }
    }

    private func visiblePanel(containing point: CGPoint, padding: CGFloat) -> NotchPanel? {
        notchPanels.values.first { panel in
            panel.isVisible
                && interactiveNotchFrame(in: panel)
                    .insetBy(dx: -padding, dy: -padding)
                    .contains(point)
        }
    }

    private func displayID(for panel: NSPanel) -> UInt32? {
        notchPanels.first(where: { $0.value === panel })?.key
    }

    /// Resolves the exact same presentation branch and geometry as SwiftUI so
    /// AppKit hover, click, scroll and drop hit testing follow the visible shell.
    private func currentVisibleSize(for panel: NSPanel) -> CGSize {
        let displayID = displayID(for: panel)
        let compactNotchSize = settings.contentSize(for: displayID)
        let isHoveringThisDisplay = appState.isHovering && appState.activeDisplayID == displayID
        let eventRoute = NotchEventPresentationPolicy.route(
            for: eventCenter.current,
            isExpanded: appState.isExpanded,
            isWalletVisible: widgetPreferences.mode(for: .wallet) != .hidden
        )
        let branchKey = NotchPresentationResolver.branchKey(
            for: NotchPresentationResolutionInput(
                hasCompletedOnboarding: settings.hasCompletedOnboarding,
                didRevealOnboarding: appState.isExpanded,
                isExpanded: appState.isExpanded,
                screenLockBranchKey: screenLock.currentPresentation?.branchKey,
                eventRoute: eventRoute,
                hasCall: calls.current != nil,
                isSceneDropTargetVisible: scenes.isDropTargetVisible,
                isFileDropTargetVisible: fileShelf.isDropTargetVisible,
                batteryBranchKey: batteryAlerts.currentPresentation?.branchKey,
                focusBranchKey: focusMode.currentPresentation?.branchKey,
                hasWalletContribution: wallet.currentContribution != nil,
                hasImportantEvent: eventCountdown.importantReminderEvent != nil,
                isEventDetailPresented: eventCountdown.isDetailPresented,
                hasTrackedEvent: eventCountdown.trackedEvent != nil,
                liveActivityBranchKey: liveActivities.current?.branchKey,
                hasHUD: hud.current != nil,
                hasEvent: eventCountdown.presentation != nil,
                hasMedia: nowPlaying.track != nil,
                hasScene: scenes.activeScene != nil
            )
        )
        let selected = fileShelf.isPresented
            ? NotchWidget.files
            : widgetPreferences.selectedWidget
        let effectiveSelection = selected == .media && nowPlaying.track == nil ? .calendar : selected
        let widgetSize = effectiveSelection == .media && nowPlaying.track?.videoPresentation == nil
            ? NotchWidgetMetrics.audioExpandedSize
            : NotchWidgetMetrics.expandedSize
        let callSize = calls.current.map {
            CallOverlayMetrics.size(for: $0, notchSize: compactNotchSize)
        } ?? (compactNotchSize == .small
            ? CallOverlayMetrics.incomingSize
            : CallOverlayMetrics.mediumSize)

        return NotchLayoutCoordinator.visibleSize(
            for: NotchContentLayoutRequest(
                branchKey: branchKey,
                baseBodySize: CGSize(
                    width: CGFloat(settings.collapsedWidth),
                    height: CGFloat(settings.collapsedHeight)
                ),
                expandedFallbackBodySize: CGSize(
                    width: max(CGFloat(settings.expandedWidth), CalendarNotchMetrics.expandedSize.width),
                    height: CalendarNotchMetrics.expandedSize.height
                ),
                onboardingBodySize: OnboardingMetrics.expandedStepSize,
                expandedWidgetBodySize: widgetSize,
                batteryBodyWidth: batteryAlerts.currentPresentation
                    .map(BatteryAlertMetrics.width(for:)) ?? BatteryAlertMetrics.chargingWidth,
                callBodySize: callSize,
                mediaPreferredWidth: nowPlaying.track?.compactPresentation.preferredWidth
                    ?? NowPlayingMetrics.collapsedWidth,
                compactSize: compactNotchSize,
                isHovering: isHoveringThisDisplay,
                showsCollapsedMusicMarquee: isHoveringThisDisplay
            )
        )
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var fileShelf: FileShelfController?
    weak var appState: AppState?
    weak var dropIntelligence: DropIntelligenceController?
    weak var scenes: WallpaperSceneController?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // MARK: NSDraggingDestination — files dropped on the notch drop zone.

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.types?.contains(.fileURL) == true ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = draggedURLs(from: sender)
        if WallpaperSceneController.isSceneDrop(urls), scenes?.isDropTargetVisible == true {
            scenes?.setHoveringDropZone(true)
            fileShelf?.setHoveringDropZone(false)
        } else {
            scenes?.setHoveringDropZone(false)
            fileShelf?.setHoveringDropZone(true)
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        fileShelf?.setHoveringDropZone(false)
        scenes?.setHoveringDropZone(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = draggedURLs(from: sender)
        guard !urls.isEmpty else { return false }

        if WallpaperSceneController.isSceneDrop(urls),
           let scenes,
           scenes.isDropTargetVisible,
           let url = urls.first {
            Task { @MainActor [weak scenes] in
                _ = await scenes?.importAndApply(from: url)
            }
            return true
        }

        guard let fileShelf else { return false }
        Task { @MainActor [weak fileShelf, weak appState, weak dropIntelligence] in
            guard let fileShelf else { return }
            _ = await fileShelf.add(urls)
            dropIntelligence?.analyze(fileShelf.latestAddedItems)
            appState?.expand()
        }
        return true
    }

    private func draggedURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
