//
//  ClipboardControllerTests.swift
//  NotchLandTests
//

import AppKit
import Foundation
import Testing
@testable import NotchLand

@MainActor
struct ClipboardControllerTests {
    private func makeSystem() -> (
        controller: ClipboardController,
        defaults: UserDefaults,
        pasteboard: NSPasteboard
    ) {
        let defaults = UserDefaults(
            suiteName: "ClipboardControllerTests.\(UUID().uuidString)"
        )!
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ClipboardControllerTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return (
            ClipboardController(defaults: defaults, pasteboard: pasteboard),
            defaults,
            pasteboard
        )
    }

    @Test func captureNormalizesDeduplicatesAndRestoresText() {
        let system = makeSystem()
        let first = system.controller.capture(text: "  First snippet\n")!
        _ = system.controller.capture(text: "Second snippet")
        let duplicate = system.controller.capture(text: "First snippet")

        let restored = ClipboardController(
            defaults: system.defaults,
            pasteboard: system.pasteboard
        )

        #expect(system.controller.items.count == 2)
        #expect(duplicate?.id == first.id)
        #expect(restored.items.map(\.text) == ["First snippet", "Second snippet"])
    }

    @Test func pinnedItemsSortFirstAndSurviveClear() {
        let system = makeSystem()
        let pinned = system.controller.capture(text: "Keep me")!
        _ = system.controller.capture(text: "Remove me")

        system.controller.togglePinned(pinned)
        system.controller.clearUnpinned()

        #expect(system.controller.items.map(\.id) == [pinned.id])
        #expect(system.controller.items.first?.isPinned == true)
    }

    @Test func copyWritesTextToInjectedPasteboard() {
        let system = makeSystem()
        let item = system.controller.capture(text: "Copied from NotchLand")!

        system.controller.copy(item)

        #expect(system.pasteboard.string(forType: .string) == "Copied from NotchLand")
    }

    @Test func monitoringPreferencePersists() {
        let system = makeSystem()

        system.controller.setMonitoringEnabled(false)
        let restored = ClipboardController(
            defaults: system.defaults,
            pasteboard: system.pasteboard
        )

        #expect(system.controller.isMonitoring == false)
        #expect(restored.monitoringPreference == false)
    }

    @Test func deleteRemovesOnlySelectedItem() {
        let system = makeSystem()
        let deleted = system.controller.capture(text: "Delete")!
        let retained = system.controller.capture(text: "Retain")!

        system.controller.delete(deleted)

        #expect(system.controller.items.map(\.id) == [retained.id])
    }
}

