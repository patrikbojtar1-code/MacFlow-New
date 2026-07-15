//
//  QuickActionsControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct QuickActionsControllerTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "QuickActionsControllerTests.\(UUID().uuidString)")!
    }

    private func makeTemporaryApplication(named name: String = "Test App") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickActionsControllerTests.\(UUID().uuidString)", isDirectory: true)
        let application = root.appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        return application
    }

    @Test func newControllerProvidesCoreSystemActions() {
        let controller = QuickActionsController(defaults: makeDefaults())

        #expect(controller.items.count == 6)
        #expect(controller.items.allSatisfy { $0.isBuiltIn })
        #expect(controller.items.map(\.title).contains("Downloads"))
        #expect(controller.items.map(\.title).contains("Screenshot"))
    }

    @Test func customApplicationPersistsAcrossRelaunch() throws {
        let defaults = makeDefaults()
        let application = try makeTemporaryApplication(named: "Notch Tool")
        defer { try? FileManager.default.removeItem(at: application.deletingLastPathComponent()) }
        let controller = QuickActionsController(defaults: defaults)

        let added = controller.addApplications([application])
        let restored = QuickActionsController(defaults: defaults)

        #expect(added == 1)
        #expect(restored.items.last?.title == "Notch Tool")
        #expect(restored.items.last?.isBuiltIn == false)
    }

    @Test func duplicateAndNonApplicationPathsAreRejected() throws {
        let controller = QuickActionsController(defaults: makeDefaults())
        let application = try makeTemporaryApplication()
        let textFile = application.deletingLastPathComponent().appendingPathComponent("readme.txt")
        FileManager.default.createFile(atPath: textFile.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: application.deletingLastPathComponent()) }

        #expect(controller.addApplications([application, application, textFile]) == 1)
        #expect(controller.addApplications([application]) == 0)
    }

    @Test func removingCustomActionCannotRemoveBuiltInAction() throws {
        let controller = QuickActionsController(defaults: makeDefaults())
        let application = try makeTemporaryApplication()
        defer { try? FileManager.default.removeItem(at: application.deletingLastPathComponent()) }
        controller.addApplications([application])
        let custom = controller.items.last!
        let builtIn = controller.items.first!

        controller.remove(builtIn)
        controller.remove(custom)

        #expect(controller.items.count == 6)
        #expect(controller.items.contains(where: { $0.id == builtIn.id }))
        #expect(!controller.items.contains(where: { $0.id == custom.id }))
    }

    @Test func resetRestoresOnlyDefaults() throws {
        let controller = QuickActionsController(defaults: makeDefaults())
        let application = try makeTemporaryApplication()
        defer { try? FileManager.default.removeItem(at: application.deletingLastPathComponent()) }
        controller.addApplications([application])

        controller.resetToDefaults()

        #expect(controller.items.count == 6)
        #expect(controller.items.allSatisfy { $0.isBuiltIn })
    }
}
