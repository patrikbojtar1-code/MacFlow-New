//
//  TodoController.swift
//  NotchLand
//
//  Local task store with favourites, completion and automatic archiving.
//

import Combine
import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var completedAt: Date?
    var isFavorite: Bool
    var isArchived: Bool

    var isCompleted: Bool { completedAt != nil }
}

@MainActor
final class TodoController: ObservableObject {
    @Published private(set) var items: [TodoItem] = []

    private enum Constants {
        static let storageKey = "todo.items.v1"
        static let maximumCount = 100
        static let automaticArchiveDelay: TimeInterval = 24 * 60 * 60
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
        archiveEligibleItems()
    }

    var activeItems: [TodoItem] {
        items
            .filter { !$0.isArchived }
            .sorted(by: Self.taskOrdering)
    }

    var archivedItems: [TodoItem] {
        items
            .filter(\.isArchived)
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    var remainingCount: Int {
        items.filter { !$0.isArchived && !$0.isCompleted }.count
    }

    @discardableResult
    func add(title: String) -> TodoItem? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let item = TodoItem(
            id: UUID(),
            title: normalized,
            createdAt: Date(),
            completedAt: nil,
            isFavorite: false,
            isArchived: false
        )
        items.append(item)
        if items.count > Constants.maximumCount {
            removeOldestDisposableItem()
        }
        persist()
        NotchHaptics.perform(.confirmation)
        return item
    }

    func toggleCompleted(_ item: TodoItem, at date: Date = .now) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if items[index].isCompleted {
            items[index].completedAt = nil
            items[index].isArchived = false
        } else {
            items[index].completedAt = date
        }
        persist()
        NotchHaptics.perform(.confirmation)
    }

    func toggleFavorite(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
        persist()
        NotchHaptics.perform(.navigation)
    }

    func archiveCompleted() {
        var changed = false
        for index in items.indices where items[index].isCompleted && !items[index].isArchived {
            items[index].isArchived = true
            changed = true
        }
        guard changed else { return }
        persist()
    }

    func archiveEligibleItems(now: Date = .now) {
        var changed = false
        for index in items.indices {
            guard let completedAt = items[index].completedAt,
                  !items[index].isArchived,
                  now.timeIntervalSince(completedAt) >= Constants.automaticArchiveDelay else { continue }
            items[index].isArchived = true
            changed = true
        }
        if changed { persist() }
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        persist()
        NotchHaptics.perform(.navigation)
    }

    func clearArchive() {
        items.removeAll(where: \.isArchived)
        persist()
    }

    private static func taskOrdering(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted && rhs.isCompleted }
        if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
        return lhs.createdAt > rhs.createdAt
    }

    private func removeOldestDisposableItem() {
        if let index = items.indices
            .filter({ items[$0].isArchived || items[$0].isCompleted })
            .min(by: { items[$0].createdAt < items[$1].createdAt }) {
            items.remove(at: index)
            return
        }
        if let oldest = items.indices.min(by: { items[$0].createdAt < items[$1].createdAt }) {
            items.remove(at: oldest)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: Constants.storageKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        items = Array(decoded.prefix(Constants.maximumCount))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Constants.storageKey)
    }
}
