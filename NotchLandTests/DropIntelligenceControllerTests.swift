//
//  DropIntelligenceControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct DropIntelligenceControllerTests {
    private func item(_ name: String, isDirectory: Bool = false) -> FileShelfItem {
        FileShelfItem(
            url: URL(fileURLWithPath: "/tmp/\(name)", isDirectory: isDirectory),
            isDirectory: isDirectory,
            metadataDescription: isDirectory ? "Folder" : "File"
        )
    }

    @Test func classifiesCommonContentWithoutFilesystemAccess() {
        #expect(DropContentClassifier.classify([item("Design.png")]) == .image)
        #expect(DropContentClassifier.classify([item("Contract.pdf")]) == .pdf)
        #expect(DropContentClassifier.classify([item("Movie.mov")]) == .video)
        #expect(DropContentClassifier.classify([item("Track.m4a")]) == .audio)
        #expect(DropContentClassifier.classify([item("Source.swift")]) == .code)
        #expect(DropContentClassifier.classify([item("Archive.zip")]) == .archive)
        #expect(DropContentClassifier.classify([item("Project", isDirectory: true)]) == .folder)
    }

    @Test func multipleItemsUseBatchClassification() {
        let items = [item("One.png"), item("Two.pdf")]

        #expect(DropContentClassifier.classify(items) == .multiple)
        #expect(DropSuggestionEngine.suggestions(for: .multiple) == [.airDrop, .copyPaths, .shortcuts])
    }

    @Test func folderSuggestionsAvoidRecursiveWork() {
        #expect(DropSuggestionEngine.suggestions(for: .folder) == [.reveal, .copyPaths, .shortcuts])
    }

    @Test func controllerPublishesAndDismissesAnalysis() {
        let controller = DropIntelligenceController()

        controller.analyze([item("Photo.heic")])
        #expect(controller.current?.kind == .image)
        #expect(controller.current?.suggestions == [.quickLook, .airDrop, .shortcuts])

        controller.dismiss()
        #expect(controller.current == nil)
    }
}
