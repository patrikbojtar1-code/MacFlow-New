//
//  TodoControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct TodoControllerTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TodoControllerTests.\(UUID().uuidString)")!
    }

    @Test func addNormalizesTitleAndRestoresItems() {
        let defaults = makeDefaults()
        let controller = TodoController(defaults: defaults)

        let item = controller.add(title: "  Polish animations  \n")
        let restored = TodoController(defaults: defaults)

        #expect(item?.title == "Polish animations")
        #expect(restored.activeItems.count == 1)
        #expect(restored.activeItems.first?.id == item?.id)
        #expect(controller.add(title: "   \n") == nil)
    }

    @Test func favouritesSortBeforeOtherOpenTasks() {
        let controller = TodoController(defaults: makeDefaults())
        let favourite = controller.add(title: "Favourite")!
        let newer = controller.add(title: "Newer")!

        controller.toggleFavorite(favourite)

        #expect(controller.activeItems.map(\.id) == [favourite.id, newer.id])
        #expect(controller.remainingCount == 2)
    }

    @Test func completionMovesTaskBehindOpenTasksAndCanBeUndone() {
        let controller = TodoController(defaults: makeDefaults())
        let completed = controller.add(title: "Complete me")!
        let open = controller.add(title: "Keep open")!

        controller.toggleCompleted(completed)

        #expect(controller.activeItems.map(\.id) == [open.id, completed.id])
        #expect(controller.remainingCount == 1)
        #expect(controller.activeItems.last?.isCompleted == true)

        controller.toggleCompleted(completed)

        #expect(controller.remainingCount == 2)
        #expect(controller.items.first(where: { $0.id == completed.id })?.completedAt == nil)
    }

    @Test func completedTaskAutomaticallyArchivesAfterOneDay() {
        let defaults = makeDefaults()
        let controller = TodoController(defaults: defaults)
        let item = controller.add(title: "Archive later")!
        let now = Date()

        controller.toggleCompleted(item, at: now.addingTimeInterval(-(25 * 60 * 60)))
        controller.archiveEligibleItems(now: now)

        #expect(controller.activeItems.isEmpty)
        #expect(controller.archivedItems.map(\.id) == [item.id])
        #expect(TodoController(defaults: defaults).archivedItems.map(\.id) == [item.id])
    }

    @Test func archiveManagementKeepsOpenTasksSafe() {
        let controller = TodoController(defaults: makeDefaults())
        let done = controller.add(title: "Done")!
        let open = controller.add(title: "Open")!
        controller.toggleCompleted(done)

        controller.archiveCompleted()
        controller.clearArchive()

        #expect(controller.items.map(\.id) == [open.id])
        #expect(controller.remainingCount == 1)
    }
}
