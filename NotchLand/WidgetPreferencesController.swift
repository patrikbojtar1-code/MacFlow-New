//
//  WidgetPreferencesController.swift
//  NotchLand
//
//  Persistent dashboard ordering and visibility preferences.
//

import Combine
import Foundation

enum WidgetVisibilityMode: String, CaseIterable, Identifiable, Sendable {
    case pinned
    case automatic
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .automatic: "Automatic"
        case .hidden: "Hidden"
        }
    }

    var symbol: String {
        switch self {
        case .pinned: "pin.fill"
        case .automatic: "sparkles"
        case .hidden: "eye.slash"
        }
    }
}

@MainActor
final class WidgetPreferencesController: ObservableObject {
    @Published private(set) var orderedWidgets: [NotchWidget]
    @Published private(set) var visibilityModes: [NotchWidget: WidgetVisibilityMode]
    @Published private(set) var selectedWidget: NotchWidget

    private enum Keys {
        static let order = "widgets.order.v1"
        static let enabled = "widgets.enabled.v1"
        static let modes = "widgets.visibilityModes.v2"
        static let selected = "notch.selectedWidget"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedOrder = defaults.stringArray(forKey: Keys.order)?
            .compactMap(NotchWidget.init(rawValue:)) ?? []
        let uniqueSavedOrder = savedOrder.reduce(into: [NotchWidget]()) { result, widget in
            guard !result.contains(widget) else { return }
            result.append(widget)
        }
        orderedWidgets = uniqueSavedOrder + NotchWidget.allCases.filter { !uniqueSavedOrder.contains($0) }

        if let savedModes = defaults.dictionary(forKey: Keys.modes) as? [String: String] {
            visibilityModes = Dictionary(uniqueKeysWithValues: NotchWidget.allCases.map { widget in
                let mode = savedModes[widget.rawValue].flatMap(WidgetVisibilityMode.init(rawValue:))
                    ?? Self.defaultMode(for: widget)
                return (widget, mode)
            })
        } else if let savedEnabled = defaults.stringArray(forKey: Keys.enabled) {
            let restored = Set(savedEnabled.compactMap(NotchWidget.init(rawValue:)))
            let enabled = restored.isEmpty ? Set(NotchWidget.allCases) : restored
            visibilityModes = Dictionary(uniqueKeysWithValues: NotchWidget.allCases.map { widget in
                let mode: WidgetVisibilityMode
                if enabled.contains(widget) {
                    mode = .pinned
                } else if widget == .wallet {
                    mode = .automatic
                } else {
                    mode = .hidden
                }
                return (widget, mode)
            })
        } else {
            visibilityModes = Dictionary(uniqueKeysWithValues: NotchWidget.allCases.map {
                ($0, Self.defaultMode(for: $0))
            })
        }
        selectedWidget = defaults.string(forKey: Keys.selected)
            .flatMap(NotchWidget.init(rawValue:)) ?? .calendar
        ensureAtLeastOneVisibleWidget()
        ensureSelectedWidgetIsVisible()
        persist()
    }

    var visibleWidgets: [NotchWidget] {
        orderedWidgets.filter { mode(for: $0) != .hidden }
    }

    var pinnedWidgets: [NotchWidget] {
        orderedWidgets.filter { mode(for: $0) == .pinned }
    }

    func mode(for widget: NotchWidget) -> WidgetVisibilityMode {
        visibilityModes[widget] ?? .pinned
    }

    func isEnabled(_ widget: NotchWidget) -> Bool {
        mode(for: widget) != .hidden
    }

    func setEnabled(_ isEnabled: Bool, for widget: NotchWidget) {
        setMode(isEnabled ? .pinned : .hidden, for: widget)
    }

    func setMode(_ mode: WidgetVisibilityMode, for widget: NotchWidget) {
        guard mode != .hidden || visibleWidgets.count > 1 || self.mode(for: widget) == .hidden else {
            NotchHaptics.perform(.rejection)
            return
        }
        guard self.mode(for: widget) != mode else { return }
        visibilityModes[widget] = mode
        ensureSelectedWidgetIsVisible()
        persist()
        NotchHaptics.perform(.navigation)
    }

    func select(_ widget: NotchWidget) {
        guard mode(for: widget) != .hidden else {
            NotchHaptics.perform(.rejection)
            return
        }
        guard selectedWidget != widget else { return }
        selectedWidget = widget
        persist()
        NotchHaptics.perform(.navigation)
    }

    func move(_ widget: NotchWidget, by offset: Int) {
        guard let source = orderedWidgets.firstIndex(of: widget) else { return }
        let destination = min(max(source + offset, orderedWidgets.startIndex), orderedWidgets.index(before: orderedWidgets.endIndex))
        guard source != destination else { return }
        let moved = orderedWidgets.remove(at: source)
        orderedWidgets.insert(moved, at: destination)
        persist()
        NotchHaptics.perform(.navigation)
    }

    func move(_ widget: NotchWidget, before target: NotchWidget) {
        guard widget != target,
              let source = orderedWidgets.firstIndex(of: widget),
              let targetIndex = orderedWidgets.firstIndex(of: target) else { return }
        let moved = orderedWidgets.remove(at: source)
        let destination = source < targetIndex ? targetIndex - 1 : targetIndex
        orderedWidgets.insert(moved, at: destination)
        persist()
        NotchHaptics.perform(.navigation)
    }

    func applyConfiguration(
        preferredOrder: [NotchWidget],
        pinned: Set<NotchWidget>,
        automatic: Set<NotchWidget>
    ) {
        let uniqueOrder = preferredOrder.reduce(into: [NotchWidget]()) { result, widget in
            guard !result.contains(widget) else { return }
            result.append(widget)
        }
        orderedWidgets = uniqueOrder + NotchWidget.allCases.filter { !uniqueOrder.contains($0) }
        visibilityModes = Dictionary(uniqueKeysWithValues: NotchWidget.allCases.map { widget in
            let mode: WidgetVisibilityMode
            if pinned.contains(widget) {
                mode = .pinned
            } else if automatic.contains(widget) {
                mode = .automatic
            } else {
                mode = .hidden
            }
            return (widget, mode)
        })
        ensureAtLeastOneVisibleWidget()
        ensureSelectedWidgetIsVisible()
        persist()
        NotchHaptics.perform(.confirmation)
    }

    func reset() {
        orderedWidgets = NotchWidget.allCases
        visibilityModes = Dictionary(uniqueKeysWithValues: NotchWidget.allCases.map {
            ($0, Self.defaultMode(for: $0))
        })
        selectedWidget = .calendar
        persist()
        NotchHaptics.perform(.navigation)
    }

    private func persist() {
        defaults.set(orderedWidgets.map(\.rawValue), forKey: Keys.order)
        defaults.set(visibleWidgets.map(\.rawValue), forKey: Keys.enabled)
        defaults.set(
            Dictionary(uniqueKeysWithValues: visibilityModes.map { ($0.key.rawValue, $0.value.rawValue) }),
            forKey: Keys.modes
        )
        defaults.set(selectedWidget.rawValue, forKey: Keys.selected)
    }

    private func ensureAtLeastOneVisibleWidget() {
        guard !visibilityModes.values.contains(where: { $0 != .hidden }),
              let first = orderedWidgets.first else { return }
        visibilityModes[first] = .pinned
    }

    private func ensureSelectedWidgetIsVisible() {
        guard mode(for: selectedWidget) == .hidden,
              let fallback = visibleWidgets.first else { return }
        selectedWidget = fallback
    }

    private static func defaultMode(for widget: NotchWidget) -> WidgetVisibilityMode {
        widget == .wallet ? .automatic : .pinned
    }
}
