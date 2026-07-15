//
//  QuickNotesController.swift
//  NotchLand
//
//  Local-only notes store used by the notch widget. No content leaves the Mac.
//

import AppKit
import Combine
import Foundation

struct QuickNote: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool

    var title: String {
        content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? "New note"
    }

    var preview: String {
        let lines = content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.dropFirst().first ?? (content.isEmpty ? "Start typing…" : content)
    }
}

@MainActor
final class QuickNotesController: ObservableObject {
    @Published private(set) var notes: [QuickNote] = []
    @Published private(set) var selectedID: UUID?

    private enum Keys {
        static let notes = "quickNotes.items.v1"
        static let selectedID = "quickNotes.selectedID"
        static let maximumCount = 50
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    var selectedNote: QuickNote? {
        guard let selectedID else { return nil }
        return notes.first { $0.id == selectedID }
    }

    @discardableResult
    func createNote() -> QuickNote {
        let now = Date()
        let note = QuickNote(
            id: UUID(),
            content: "",
            createdAt: now,
            modifiedAt: now,
            isPinned: false
        )
        notes.insert(note, at: 0)
        if notes.count > Keys.maximumCount {
            notes = Array(notes.prefix(Keys.maximumCount))
        }
        selectedID = note.id
        persist()
        NotchHaptics.perform(.navigation)
        return note
    }

    func select(_ note: QuickNote) {
        guard notes.contains(where: { $0.id == note.id }) else { return }
        selectedID = note.id
        persistSelection()
    }

    func updateContent(id: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].content != content else { return }
        notes[index].content = content
        notes[index].modifiedAt = Date()
        sortNotes()
        persist()
    }

    func togglePinned(_ note: QuickNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isPinned.toggle()
        notes[index].modifiedAt = Date()
        sortNotes()
        persist()
        NotchHaptics.perform(.navigation)
    }

    func delete(_ note: QuickNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let wasSelected = selectedID == note.id
        notes.remove(at: index)
        if wasSelected {
            selectedID = notes.indices.contains(index)
                ? notes[index].id
                : notes.last?.id
        }
        persist()
        NotchHaptics.perform(.navigation)
    }

    func copy(_ note: QuickNote) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.content, forType: .string)
        NotchHaptics.perform(.confirmation)
    }

    private func restore() {
        if let data = defaults.data(forKey: Keys.notes),
           let decoded = try? JSONDecoder().decode([QuickNote].self, from: data) {
            notes = Array(decoded.prefix(Keys.maximumCount))
            sortNotes()
        }

        if let rawID = defaults.string(forKey: Keys.selectedID),
           let id = UUID(uuidString: rawID),
           notes.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = notes.first?.id
        }
    }

    private func sortNotes() {
        notes.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(notes) {
            defaults.set(data, forKey: Keys.notes)
        }
        persistSelection()
    }

    private func persistSelection() {
        defaults.set(selectedID?.uuidString, forKey: Keys.selectedID)
    }
}
