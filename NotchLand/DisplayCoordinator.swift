//
//  DisplayCoordinator.swift
//  MacFlow
//
//  Canonical display inventory and selection policy for notch and wallpaper
//  runtimes. AppKit screen objects stay on MainActor; immutable snapshots are
//  safe to use in tests and background policy decisions.
//

import AppKit
import Combine
import CoreGraphics

nonisolated enum NotchDisplayPolicy: String, CaseIterable, Identifiable, Sendable {
    case internalDisplay
    case mainDisplay
    case selectedDisplays
    case allDisplays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalDisplay: "Built-in display"
        case .mainDisplay: "Main display"
        case .selectedDisplays: "Selected displays"
        case .allDisplays: "All displays"
        }
    }
}

nonisolated struct DisplaySnapshot: Identifiable, Equatable, Sendable {
    let id: UInt32
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let scaleFactor: CGFloat
    let isBuiltIn: Bool
    let isMain: Bool
    let hasHardwareNotch: Bool
}

nonisolated struct DisplayNotchConfiguration: Codable, Equatable, Sendable {
    var contentSize: NotchSize
    var horizontalOffset: Double

    init(contentSize: NotchSize, horizontalOffset: Double = 0) {
        self.contentSize = contentSize
        self.horizontalOffset = horizontalOffset
    }
}

nonisolated enum DisplaySelectionResolver {
    static func selectedIDs(
        policy: NotchDisplayPolicy,
        selectedIDs: Set<UInt32>,
        displays: [DisplaySnapshot]
    ) -> [UInt32] {
        guard !displays.isEmpty else { return [] }

        let resolved: [DisplaySnapshot]
        switch policy {
        case .internalDisplay:
            resolved = displays.filter(\.isBuiltIn)
        case .mainDisplay:
            resolved = displays.filter(\.isMain)
        case .selectedDisplays:
            resolved = displays.filter { selectedIDs.contains($0.id) }
        case .allDisplays:
            resolved = displays
        }

        if !resolved.isEmpty {
            return resolved.map(\.id)
        }
        return [displays.first(where: \.isMain)?.id ?? displays[0].id]
    }
}

@MainActor
final class DisplayCoordinator: ObservableObject {
    @Published private(set) var displays: [DisplaySnapshot] = []
    @Published private(set) var revision = 0

    private let notificationCenter: NotificationCenter
    private var screenObserver: NSObjectProtocol?
    private var screensByID: [UInt32: NSScreen] = [:]

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        refresh()
    }

    deinit {
        if let screenObserver {
            notificationCenter.removeObserver(screenObserver)
        }
    }

    func start() {
        guard screenObserver == nil else {
            refresh()
            return
        }
        refresh()
        screenObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        if let screenObserver {
            notificationCenter.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    func refresh(screens: [NSScreen] = NSScreen.screens) {
        let mainID = NSScreen.main?.displayID
        var nextScreens: [UInt32: NSScreen] = [:]
        let nextDisplays = screens.compactMap { screen -> DisplaySnapshot? in
            guard let id = screen.displayID else { return nil }
            nextScreens[id] = screen
            return DisplaySnapshot(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                scaleFactor: screen.backingScaleFactor,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMain: id == mainID,
                hasHardwareNotch: screen.auxiliaryTopLeftArea != nil
                    || screen.auxiliaryTopRightArea != nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.id < rhs.id
        }

        screensByID = nextScreens
        if nextDisplays != displays {
            displays = nextDisplays
            revision &+= 1
        }
    }

    func selectedScreens(
        policy: NotchDisplayPolicy,
        selectedIDs: Set<UInt32>
    ) -> [NSScreen] {
        DisplaySelectionResolver.selectedIDs(
            policy: policy,
            selectedIDs: selectedIDs,
            displays: displays
        )
        .compactMap { screensByID[$0] }
    }

    func primaryNotchScreen(
        policy: NotchDisplayPolicy,
        selectedIDs: Set<UInt32>,
        fallbackPanel: NSPanel? = nil
    ) -> NSScreen? {
        let selected = selectedScreens(policy: policy, selectedIDs: selectedIDs)
        if let hardware = selected.first(where: { screen in
            screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil
        }) {
            return hardware
        }
        return selected.first ?? fallbackPanel?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
