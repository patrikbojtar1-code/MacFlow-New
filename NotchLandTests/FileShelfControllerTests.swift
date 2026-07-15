//
//  FileShelfControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct FileShelfControllerTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "FileShelfControllerTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func makeFile(named name: String = UUID().uuidString) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchLandFileShelfTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("NotchLand".utf8).write(to: url)
        return url
    }

    @Test func addPersistsAndRestoresFile() async throws {
        let defaults = makeDefaults()
        let settings = NotchSettings()
        settings.fileShelfEnabled = true
        let file = try makeFile()

        let controller = FileShelfController(settings: settings, defaults: defaults)
        #expect(await controller.add([file]) == 1)
        #expect(controller.items.map(\.url) == [file.standardizedFileURL])

        let restored = FileShelfController(settings: settings, defaults: defaults)
        await restored.waitForRestoration()
        #expect(restored.items.count == 1)
        #expect(restored.items.first?.url.standardizedFileURL == file.standardizedFileURL)
    }

    @Test func duplicateDropDoesNotCreateDuplicateItem() async throws {
        let defaults = makeDefaults()
        let settings = NotchSettings()
        settings.fileShelfEnabled = true
        let file = try makeFile()
        let controller = FileShelfController(settings: settings, defaults: defaults)

        #expect(await controller.add([file, file]) == 1)
        #expect(await controller.add([file]) == 0)
        #expect(controller.items.count == 1)
    }

    @Test func missingFilesAreNotAdded() async {
        let defaults = makeDefaults()
        let settings = NotchSettings()
        settings.fileShelfEnabled = true
        let controller = FileShelfController(settings: settings, defaults: defaults)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        #expect(await controller.add([missing]) == 0)
        #expect(controller.items.isEmpty)
    }

    @Test func removeAllClearsPersistenceAndPresentation() async throws {
        let defaults = makeDefaults()
        let settings = NotchSettings()
        settings.fileShelfEnabled = true
        let controller = FileShelfController(settings: settings, defaults: defaults)
        _ = await controller.add([try makeFile()])

        controller.removeAll()

        #expect(controller.items.isEmpty)
        #expect(controller.isPresented == false)
        #expect(FileShelfController(settings: settings, defaults: defaults).items.isEmpty)
    }

    @Test func restorePrunesFilesThatNoLongerExist() async throws {
        let defaults = makeDefaults()
        let settings = NotchSettings()
        settings.fileShelfEnabled = true
        let file = try makeFile()
        let controller = FileShelfController(settings: settings, defaults: defaults)
        _ = await controller.add([file])
        try FileManager.default.removeItem(at: file)

        let restored = FileShelfController(settings: settings, defaults: defaults)
        await restored.waitForRestoration()

        #expect(restored.items.isEmpty)
        #expect(FileShelfController(settings: settings, defaults: defaults).items.isEmpty)
    }

    @Test func foldersAreAcceptedWithoutEnumeratingTheirContents() async throws {
        let defaults = makeDefaults()
        let settings = NotchSettings()
        settings.fileShelfEnabled = true
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchLandFolderTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<100 {
            try Data("item".utf8).write(to: folder.appendingPathComponent("\(index).txt"))
        }
        let controller = FileShelfController(settings: settings, defaults: defaults)

        #expect(await controller.add([folder]) == 1)
        #expect(controller.items.first?.isDirectory == true)
        #expect(controller.items.first?.metadataDescription.localizedCaseInsensitiveContains("folder") == true)
    }
}
