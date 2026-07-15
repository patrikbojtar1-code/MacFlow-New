//
//  QuickNotesControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct QuickNotesControllerTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "QuickNotesControllerTests.\(UUID().uuidString)")!
    }

    @Test func createEditAndRestoreNote() {
        let defaults = makeDefaults()
        let controller = QuickNotesController(defaults: defaults)
        let note = controller.createNote()
        controller.updateContent(id: note.id, content: "Roadmap\nShip Quick Notes")

        let restored = QuickNotesController(defaults: defaults)

        #expect(restored.notes.count == 1)
        #expect(restored.selectedNote?.id == note.id)
        #expect(restored.selectedNote?.title == "Roadmap")
        #expect(restored.selectedNote?.preview == "Ship Quick Notes")
    }

    @Test func pinnedNotesSortBeforeNewerNotes() {
        let defaults = makeDefaults()
        let controller = QuickNotesController(defaults: defaults)
        let pinned = controller.createNote()
        controller.updateContent(id: pinned.id, content: "Pinned")
        let newer = controller.createNote()
        controller.updateContent(id: newer.id, content: "Newer")

        controller.togglePinned(pinned)

        #expect(controller.notes.first?.id == pinned.id)
        #expect(controller.notes.first?.isPinned == true)
    }

    @Test func deletingSelectedNoteSelectsAnotherNote() {
        let defaults = makeDefaults()
        let controller = QuickNotesController(defaults: defaults)
        let first = controller.createNote()
        let second = controller.createNote()
        #expect(controller.selectedID == second.id)

        controller.delete(second)

        #expect(controller.notes.count == 1)
        #expect(controller.selectedID == first.id)
    }

    @Test func emptyFirstLineDoesNotBecomeTitle() {
        let defaults = makeDefaults()
        let controller = QuickNotesController(defaults: defaults)
        let note = controller.createNote()

        controller.updateContent(id: note.id, content: "\n   \nActual title\nBody")

        #expect(controller.selectedNote?.title == "Actual title")
        #expect(controller.selectedNote?.preview == "Body")
    }
}
