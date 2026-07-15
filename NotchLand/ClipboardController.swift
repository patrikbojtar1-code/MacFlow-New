//
//  ClipboardController.swift
//  NotchLand
//
//  Local-only text clipboard history. Monitoring can be paused at any time;
//  content is never uploaded or shared outside the Mac.
//

import AppKit
import Combine
import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var copiedAt: Date
    var isPinned: Bool

    var title: String {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? "Text"
    }

    var lineCount: Int {
        max(1, text.components(separatedBy: .newlines).count)
    }
}

@MainActor
final class ClipboardController: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isMonitoring = false

    private enum Constants {
        static let itemsKey = "clipboard.items.v1"
        static let monitoringKey = "clipboard.monitoringEnabled"
        static let maximumItemCount = 30
        static let maximumCharacterCount = 50_000
        static let pollingNanoseconds: UInt64 = 700_000_000
    }

    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private var monitorTask: Task<Void, Never>?
    private var lastChangeCount: Int

    init(
        defaults: UserDefaults = .standard,
        pasteboard: NSPasteboard = .general
    ) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        restore()
    }

    var monitoringPreference: Bool {
        defaults.object(forKey: Constants.monitoringKey) as? Bool ?? true
    }

    func startMonitoring() {
        guard monitoringPreference, monitorTask == nil else { return }
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Constants.pollingNanoseconds)
                guard !Task.isCancelled else { return }
                self?.capturePasteboardIfChanged()
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
    }

    func setMonitoringEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Constants.monitoringKey)
        if isEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
        NotchHaptics.perform(.navigation)
    }

    @discardableResult
    func capture(text: String, at date: Date = .now) -> ClipboardItem? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let limited = String(normalized.prefix(Constants.maximumCharacterCount))

        if let duplicateIndex = items.firstIndex(where: { $0.text == limited }) {
            var duplicate = items.remove(at: duplicateIndex)
            duplicate.copiedAt = date
            items.insert(duplicate, at: 0)
            sortItems()
            persist()
            return duplicate
        }

        let item = ClipboardItem(
            id: UUID(),
            text: limited,
            copiedAt: date,
            isPinned: false
        )
        items.insert(item, at: 0)
        trimHistory()
        sortItems()
        persist()
        return item
    }

    func copy(_ item: ClipboardItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        _ = capture(text: item.text)
        NotchHaptics.perform(.confirmation)
    }

    func togglePinned(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        sortItems()
        persist()
        NotchHaptics.perform(.navigation)
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        persist()
        NotchHaptics.perform(.navigation)
    }

    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        persist()
    }

    private func capturePasteboardIfChanged() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        guard let text = pasteboard.string(forType: .string) else { return }
        _ = capture(text: text)
    }

    private func trimHistory() {
        guard items.count > Constants.maximumItemCount else { return }
        while items.count > Constants.maximumItemCount {
            if let removable = items.lastIndex(where: { !$0.isPinned }) {
                items.remove(at: removable)
            } else {
                items.removeLast()
            }
        }
    }

    private func sortItems() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.copiedAt > $1.copiedAt
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: Constants.itemsKey),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = Array(decoded.prefix(Constants.maximumItemCount))
        sortItems()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Constants.itemsKey)
    }
}

