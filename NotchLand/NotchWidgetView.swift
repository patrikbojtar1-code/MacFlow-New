//
//  NotchWidgetView.swift
//  NotchLand
//
//  Shared expanded-widget surface. New widgets plug into this host instead of
//  adding another top-level branch to FloatingNotchView.
//

import SwiftUI

enum NotchWidget: String, CaseIterable, Identifiable {
    case media
    case calendar
    case files
    case wallet
    case timeline
    case shortcuts
    case timer
    case notes
    case tasks
    case clipboard
    case actions
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .calendar: "Calendar"
        case .files: "Files"
        case .wallet: "Wallet"
        case .timeline: "Timeline"
        case .shortcuts: "Shortcuts"
        case .timer: "Timer"
        case .notes: "Notes"
        case .tasks: "Tasks"
        case .clipboard: "Clipboard"
        case .actions: "Actions"
        case .mirror: "Mirror"
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .files: "tray.full"
        case .wallet: "bitcoinsign.circle.fill"
        case .timeline: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .shortcuts: "square.stack.3d.up.fill"
        case .timer: "timer"
        case .notes: "note.text"
        case .tasks: "checklist"
        case .clipboard: "doc.on.clipboard"
        case .actions: "bolt.fill"
        case .mirror: "video.fill"
        }
    }

    var containsPrivateContent: Bool {
        switch self {
        case .calendar, .files, .wallet, .timeline, .notes, .tasks, .clipboard, .mirror:
            true
        case .media, .shortcuts, .timer, .actions:
            false
        }
    }
}

enum NotchWidgetMetrics {
    nonisolated static let expandedSize = CGSize(width: 580, height: 318)
    nonisolated static let contentHeight: CGFloat = 244
    nonisolated static let railTopInset: CGFloat = 3
    nonisolated static let railHeight: CGFloat = 38
    nonisolated static let railBottomSpacing: CGFloat = 7
    nonisolated static let railHorizontalInset: CGFloat = 14
    nonisolated static let minimumHardwareNotchGap: CGFloat = 176
    nonisolated static let maximumHardwareNotchGap: CGFloat = 238
    nonisolated static let maximumVisibleRailWidgets = 6
}

struct ExpandedNotchWidgetHost: View {
    @Binding var selection: NotchWidget
    let track: NowPlayingService.Track?
    let morphNamespace: Namespace.ID

    @EnvironmentObject private var fileShelf: FileShelfController
    @EnvironmentObject private var clipboard: ClipboardController
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var timer: NotchTimerController
    @EnvironmentObject private var wallet: WalletContributionController
    @EnvironmentObject private var events: NotchEventCenter
    @EnvironmentObject private var shortcuts: ShortcutsBridgeController
    @EnvironmentObject private var preferences: WidgetPreferencesController
    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var biometrics: BiometricAuthenticationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            widgetRail
                .frame(height: NotchWidgetMetrics.railHeight)
                .padding(.top, NotchWidgetMetrics.railTopInset)

            Color.clear
                .frame(height: NotchWidgetMetrics.railBottomSpacing)

            widgetContent
                .id("\(selection.rawValue)-\(isPrivacyLocked)")
                .transition(reduceMotion ? .opacity : .notchSection)
                .frame(maxWidth: .infinity)
                .frame(height: NotchWidgetMetrics.contentHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: track) { _, _ in
            if selection == .media, track == nil {
                if let fallback = preferences.visibleWidgets.first(where: { $0 != .media }) {
                    select(fallback)
                }
            }
        }
        .onChange(of: preferences.visibleWidgets) { _, _ in
            ensureSelectionIsVisible()
        }
        .onChange(of: fileShelf.items.count) { _, _ in ensureSelectionIsVisible() }
        .onChange(of: clipboard.items.count) { _, _ in ensureSelectionIsVisible() }
        .onChange(of: calendar.events.count) { _, _ in ensureSelectionIsVisible() }
        .onChange(of: timer.remaining) { _, _ in ensureSelectionIsVisible() }
        .onChange(of: wallet.currentContribution) { _, _ in ensureSelectionIsVisible() }
        .onAppear(perform: ensureSelectionIsVisible)
    }

    @ViewBuilder
    private var widgetContent: some View {
        if isPrivacyLocked {
            PrivacyShieldView(widget: selection)
        } else {
            unprotectedWidgetContent
        }
    }

    @ViewBuilder
    private var unprotectedWidgetContent: some View {
        switch selection {
        case .media:
            if let track {
                NowPlayingExpandedView(track: track, morphNamespace: morphNamespace)
            } else {
                unavailableMedia
            }
        case .calendar:
            CalendarNotchView()
        case .files:
            FileShelfView()
        case .wallet:
            WalletContributionView()
        case .timeline:
            NotchTimelineView()
        case .shortcuts:
            ShortcutsBridgeView()
        case .timer:
            NotchTimerView()
        case .notes:
            QuickNotesView()
        case .tasks:
            TodoView()
        case .clipboard:
            ClipboardShelfView()
        case .actions:
            QuickActionsView()
        case .mirror:
            MirrorView()
        }
    }

    private var isPrivacyLocked: Bool {
        settings.biometricPrivacyEnabled
            && selection.containsPrivateContent
            && !biometrics.isAuthenticated
    }

    private var widgetRail: some View {
        let entries = Array(railWidgets.enumerated())
        let splitIndex = min(entries.count, max(1, (entries.count + 1) / 2))
        let leftEntries = Array(entries.prefix(splitIndex))
        let rightEntries = Array(entries.dropFirst(splitIndex))

        return HStack(spacing: 0) {
            railWing(entries: leftEntries, includesConfiguration: false)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Color.clear
                .frame(width: hardwareNotchGap)
                .accessibilityHidden(true)

            railWing(entries: rightEntries, includesConfiguration: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, NotchWidgetMetrics.railHorizontalInset)
    }

    private var hardwareNotchGap: CGFloat {
        min(
            NotchWidgetMetrics.maximumHardwareNotchGap,
            max(NotchWidgetMetrics.minimumHardwareNotchGap, CGFloat(settings.collapsedWidth))
        )
    }

    private func railWing(
        entries: [(offset: Int, element: NotchWidget)],
        includesConfiguration: Bool
    ) -> some View {
        HStack(spacing: 3) {
            ForEach(entries.indices, id: \.self) { entryIndex in
                let entry = entries[entryIndex]
                widgetRailButton(widget: entry.element, index: entry.offset)
            }

            if includesConfiguration {
                configurationMenu
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }

    private func widgetRailButton(widget: NotchWidget, index: Int) -> some View {
        let isSelected = selection == widget

        return Button {
            select(widget)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: widget.symbol)
                    .font(.system(size: 10, weight: .bold))
                if isSelected {
                    Text(widget.title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if widget == .files, !fileShelf.items.isEmpty {
                    railBadge("\(fileShelf.items.count)", isSelected: isSelected)
                }
                if widget == .clipboard, !clipboard.items.isEmpty {
                    railBadge("\(clipboard.items.count)", isSelected: isSelected)
                }
                if widget == .timeline, events.unreadCount > 0 {
                    railBadge(
                        "\(min(events.unreadCount, 99))",
                        isSelected: isSelected,
                        idleColor: .orange
                    )
                }
            }
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.68))
            .padding(.horizontal, isSelected ? 9 : 7)
            .frame(height: 27)
            .background(
                isSelected ? Color.white : Color.white.opacity(0.07),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(widget == .media && track == nil)
        .opacity(widget == .media && track == nil ? 0.36 : 1)
        .accessibilityLabel(widget.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(index < 9 ? "\(widget.title) — ⌘\(index + 1)" : widget.title)
        .modifier(WidgetKeyboardShortcut(index: index))
        .contextMenu {
            visibilityMenu(for: widget)
        }
        .draggable(widget.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let rawValue = items.first,
                  let source = NotchWidget(rawValue: rawValue) else { return false }
            withAnimation(selectionAnimation) {
                preferences.move(source, before: widget)
            }
            return true
        }
    }

    private func railBadge(
        _ value: String,
        isSelected: Bool,
        idleColor: Color = .white.opacity(0.6)
    ) -> some View {
        Text(value)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(isSelected ? .black.opacity(0.65) : idleColor)
    }

    private var configurationMenu: some View {
        Menu {
            if !overflowRailWidgets.isEmpty {
                Section("More modules") {
                    ForEach(overflowRailWidgets) { widget in
                        Button {
                            select(widget)
                        } label: {
                            Label(widget.title, systemImage: widget.symbol)
                        }
                        .disabled(widget == .media && track == nil)
                    }
                }
            }

            ForEach(preferences.orderedWidgets) { widget in
                Menu {
                    visibilityMenu(for: widget)
                } label: {
                    Label(widget.title, systemImage: widget.symbol)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 28, height: 27)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Customize modules")
    }

    @ViewBuilder
    private func visibilityMenu(for widget: NotchWidget) -> some View {
        ForEach(WidgetVisibilityMode.allCases) { mode in
            Button {
                withAnimation(selectionAnimation) {
                    preferences.setMode(mode, for: widget)
                }
            } label: {
                Label(
                    mode.title,
                    systemImage: preferences.mode(for: widget) == mode ? "checkmark" : mode.symbol
                )
            }
        }
    }

    private var railWidgets: [NotchWidget] {
        let activeWidgets = activeRailWidgets
        let capacity = NotchWidgetMetrics.maximumVisibleRailWidgets
        guard activeWidgets.count > capacity else { return activeWidgets }

        var displayed = Array(activeWidgets.prefix(capacity))
        if activeWidgets.contains(selection), !displayed.contains(selection) {
            displayed[displayed.index(before: displayed.endIndex)] = selection
        }
        return displayed
    }

    private var overflowRailWidgets: [NotchWidget] {
        activeRailWidgets.filter { !railWidgets.contains($0) }
    }

    private var activeRailWidgets: [NotchWidget] {
        preferences.orderedWidgets.filter { widget in
            switch preferences.mode(for: widget) {
            case .pinned:
                true
            case .automatic:
                isContextActive(for: widget)
            case .hidden:
                false
            }
        }
    }

    private func isContextActive(for widget: NotchWidget) -> Bool {
        switch widget {
        case .media: track != nil
        case .calendar: !calendar.events.isEmpty
        case .files: fileShelf.isPresented || !fileShelf.items.isEmpty
        case .wallet: wallet.currentContribution != nil
        case .timeline: !events.history.isEmpty
        case .shortcuts: !shortcuts.shortcuts.isEmpty
        case .timer: timer.remaining > 0
        case .clipboard: !clipboard.items.isEmpty
        case .notes, .tasks, .actions, .mirror: false
        }
    }

    private var unavailableMedia: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Nothing is playing")
                .font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func select(_ widget: NotchWidget) {
        guard widget != .media || track != nil else { return }
        NotchHaptics.perform(.navigation)
        withAnimation(selectionAnimation) {
            selection = widget
            fileShelf.isPresented = widget == .files
        }
    }

    private var contentAnimation: Animation {
        NotchMotionGraph.animation(for: .contentEnter, reduceMotion: reduceMotion)
    }

    private var selectionAnimation: Animation {
        NotchMotionGraph.animation(for: .selection, reduceMotion: reduceMotion)
    }

    private func ensureSelectionIsVisible() {
        guard !railWidgets.contains(selection),
              let fallback = railWidgets.first ?? preferences.visibleWidgets.first else { return }
        selection = fallback
        fileShelf.isPresented = fallback == .files
    }
}

private struct PrivacyShieldView: View {
    let widget: NotchWidget

    @EnvironmentObject private var biometrics: BiometricAuthenticationController
    @EnvironmentObject private var faceUnlock: FaceUnlockController
    @EnvironmentObject private var settings: NotchSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if faceUnlock.state.isCameraActive {
                FaceCameraPreview(session: faceUnlock.session)
                    .overlay(.black.opacity(0.42))
                    .transition(.opacity)
            } else {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.18), Color.black.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 52, height: 52)
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                        .frame(width: 52, height: 52)
                    Image(systemName: faceUnlock.state.isCameraActive ? "faceid" : biometrics.capability.symbol)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .symbolEffect(.pulse, isActive: biometrics.isAuthenticating && !reduceMotion)
                }

                VStack(spacing: 3) {
                    Text("\(widget.title) is private")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(shieldDetail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }

                HStack(spacing: 8) {
                    if settings.faceUnlockEnabled, faceUnlock.isEnrolled {
                        Button {
                            Task { await faceUnlock.beginUnlock() }
                        } label: {
                            Label("FACE UNLOCK", systemImage: "faceid")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                                .background(.white, in: Capsule(style: .continuous))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .disabled(faceUnlock.state.isCameraActive || faceUnlock.failedAttempts >= 3)
                    }

                    Button {
                        Task {
                            let success = await biometrics.authenticate()
                            if success { faceUnlock.resetAfterSystemAuthentication() }
                            NotchHaptics.perform(success ? .confirmation : .rejection)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: biometrics.isAuthenticating ? "ellipsis" : biometrics.capability.symbol)
                            Text(biometrics.isAuthenticating ? "AUTHENTICATING" : "SYSTEM")
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(settings.faceUnlockEnabled ? .white : .black)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(
                            settings.faceUnlockEnabled ? Color.white.opacity(0.1) : Color.white,
                            in: Capsule(style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(biometrics.isAuthenticating || !biometrics.isAvailable)
                }

                if let error = biometrics.errorMessage {
                    Text(error)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.red.opacity(0.82))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(NotchMotionGraph.animation(for: .contentEnter, reduceMotion: reduceMotion), value: biometrics.isAuthenticated)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(widget.title) privacy shield")
    }

    private var shieldDetail: String {
        switch faceUnlock.state {
        case let .scanning(challenge): challenge.instruction
        case .requestingCamera: "Preparing the camera. Frames stay only in memory."
        case let .failed(message): message
        default: "Use Face Unlock or \(biometrics.capability.title) to reveal this module."
        }
    }
}

private struct WidgetKeyboardShortcut: ViewModifier {
    let index: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(
                KeyEquivalent(Character(String(index + 1))),
                modifiers: .command
            )
        } else {
            content
        }
    }
}

struct NotchTimerView: View {
    @EnvironmentObject private var timer: NotchTimerController
    @AppStorage("notchTimer.selectedMinutes") private var selectedMinutes = 5

    private let presets = [1, 5, 10, 25]

    var body: some View {
        HStack(spacing: 30) {
            timerDial
            controls
        }
        .padding(.horizontal, 42)
        .padding(.top, 34)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timerDial: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = timer.currentRemaining(at: context.date)
            let progress = timer.progress(at: context.date)

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [.orange, .yellow, .orange], center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .orange.opacity(0.32), radius: 7)

                VStack(spacing: 4) {
                    Text(displayTime(remaining))
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(stateLabel)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            .frame(width: 136, height: 136)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Focus Timer")
                .font(.system(size: 17, weight: .bold, design: .rounded))

            if timer.state == .idle || timer.state == .finished {
                HStack(spacing: 7) {
                    ForEach(presets, id: \.self) { minutes in
                        Button {
                            selectedMinutes = minutes
                            NotchHaptics.perform(.navigation)
                        } label: {
                            Text("\(minutes)m")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(selectedMinutes == minutes ? .black : .white.opacity(0.72))
                                .frame(width: 42, height: 27)
                                .background(
                                    selectedMinutes == minutes ? Color.white : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text(timer.state == .paused ? "Ready when you are." : "Timer remains accurate while your Mac sleeps.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 9) {
                primaryButton

                if timer.state != .idle {
                    Button("Reset", role: .destructive) { timer.reset() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(.white.opacity(0.07), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch timer.state {
        case .idle, .finished:
            timerButton(title: "Start \(selectedMinutes) min", symbol: "play.fill") {
                timer.start(minutes: selectedMinutes)
            }
        case .running:
            timerButton(title: "Pause", symbol: "pause.fill") { timer.pause() }
        case .paused:
            timerButton(title: "Resume", symbol: "play.fill") { timer.resume() }
        }
    }

    private func timerButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 15)
                .frame(height: 32)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var stateLabel: String {
        switch timer.state {
        case .idle: "Ready"
        case .running: "Running"
        case .paused: "Paused"
        case .finished: "Finished"
        }
    }

    private func displayTime(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
