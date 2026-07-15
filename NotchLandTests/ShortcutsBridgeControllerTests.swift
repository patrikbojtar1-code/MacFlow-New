//
//  ShortcutsBridgeControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
private final class ShortcutsRunnerStub: ShortcutsCommandRunning {
    var names: [String]
    var output: String
    var error: Error?
    private(set) var receivedNames: [String] = []
    private(set) var receivedInputURLs: [[URL]] = []

    init(names: [String] = [], output: String = "Done", error: Error? = nil) {
        self.names = names
        self.output = output
        self.error = error
    }

    func listShortcutNames() async throws -> [String] {
        if let error { throw error }
        return names
    }

    func runShortcut(named name: String, inputURLs: [URL]) async throws -> String {
        receivedNames.append(name)
        receivedInputURLs.append(inputURLs)
        if let error { throw error }
        return output
    }
}

@MainActor
struct ShortcutsBridgeControllerTests {
    private func makeSystem(
        runner: ShortcutsRunnerStub
    ) -> (ShortcutsBridgeController, NotchEventCenter, UserDefaults) {
        let suite = "ShortcutsBridgeControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let events = NotchEventCenter(defaults: defaults)
        let controller = ShortcutsBridgeController(
            runner: runner,
            events: events,
            defaults: defaults
        )
        return (controller, events, defaults)
    }

    @Test func refreshDeduplicatesShortcutNames() async {
        let runner = ShortcutsRunnerStub(names: ["Morning", "morning", "Archive", ""])
        let (controller, _, _) = makeSystem(runner: runner)

        await controller.refresh()

        #expect(controller.shortcuts.map(\.name) == ["Morning", "Archive"])
        #expect(controller.errorMessage == nil)
    }

    @Test func favoritesSortFirstAndPersist() async {
        let runner = ShortcutsRunnerStub(names: ["Zulu", "Alpha"])
        let (controller, events, defaults) = makeSystem(runner: runner)
        await controller.refresh()
        let zulu = controller.shortcuts.first { $0.name == "Zulu" }!

        controller.toggleFavorite(zulu)

        #expect(controller.orderedShortcuts.map(\.name) == ["Zulu", "Alpha"])
        let restored = ShortcutsBridgeController(runner: runner, events: events, defaults: defaults)
        #expect(restored.favoriteNames == Set(["Zulu"]))
    }

    @Test func runPassesNameVerbatimAndPublishesSuccessEvent() async {
        let dangerousLookingName = "Build; echo should-not-be-shell"
        let runner = ShortcutsRunnerStub(output: "Release ready")
        let (controller, events, _) = makeSystem(runner: runner)

        await controller.run(NotchShortcut(name: dangerousLookingName))

        #expect(runner.receivedNames == [dangerousLookingName])
        #expect(controller.lastResult == "Release ready")
        #expect(events.history.first?.title == "\(dangerousLookingName) finished")
        #expect(events.history.first?.symbol == "checkmark.circle.fill")
    }

    @Test func failurePublishesImportantTimelineEvent() async {
        let runner = ShortcutsRunnerStub(error: ShortcutsBridgeError.commandFailed("Permission denied"))
        let (controller, events, _) = makeSystem(runner: runner)

        await controller.run(NotchShortcut(name: "Private Action"))

        #expect(controller.errorMessage == "Permission denied")
        #expect(events.history.first?.title == "Private Action failed")
        #expect(events.history.first?.priority == .important)
    }

    @Test func shelfItemsArePassedAsTypedFileInputs() async {
        let runner = ShortcutsRunnerStub(output: "Processed")
        let (controller, _, _) = makeSystem(runner: runner)
        let folder = URL(fileURLWithPath: "/tmp/Input Folder", isDirectory: true)
        let file = URL(fileURLWithPath: "/tmp/photo.png")

        await controller.run(NotchShortcut(name: "Process Files"), inputURLs: [folder, file])

        #expect(runner.receivedInputURLs == [[folder, file]])
        #expect(controller.lastResult == "Processed")
    }
}
