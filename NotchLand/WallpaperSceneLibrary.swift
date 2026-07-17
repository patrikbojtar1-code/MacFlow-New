//
//  WallpaperSceneLibrary.swift
//  NotchLand
//
//  App-owned local storage for safe image and video scenes.
//

import AppKit
import AVFoundation
import Combine
import Foundation

enum WallpaperSceneLibraryError: LocalizedError, Equatable {
    case unsupportedFormat
    case assetTooLarge
    case unreadableAsset
    case sceneNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Choose a JPEG, PNG, HEIC, MOV, MP4, or M4V file."
        case .assetTooLarge:
            "This scene is larger than the 2 GB safety limit."
        case .unreadableAsset:
            "NotchLand could not read this file."
        case .sceneNotFound:
            "The selected scene is no longer available."
        }
    }
}

@MainActor
final class WallpaperSceneLibrary: ObservableObject {
    private struct SceneIndex: Codable {
        var version: Int
        var scenes: [WallpaperScene]
        var collections: [WallpaperSceneCollection]?
    }

    @Published private(set) var scenes: [WallpaperScene] = []
    @Published private(set) var collections: [WallpaperSceneCollection] = []

    let rootDirectory: URL
    let assetsDirectory: URL
    let thumbnailsDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.rootDirectory = applicationSupport
                .appendingPathComponent("NotchLand", isDirectory: true)
                .appendingPathComponent("Scenes", isDirectory: true)
        }

        assetsDirectory = self.rootDirectory.appendingPathComponent("Assets", isDirectory: true)
        thumbnailsDirectory = self.rootDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        indexURL = self.rootDirectory.appendingPathComponent("library.json")

        prepareStorage()
        loadIndex()
        ensureFavoritesCollection()
    }

    func assetURL(for scene: WallpaperScene) -> URL {
        assetsDirectory.appendingPathComponent(scene.assetFilename, isDirectory: false)
    }

    func previewURL(for scene: WallpaperScene) -> URL {
        guard let thumbnailFilename = scene.thumbnailFilename else {
            return assetURL(for: scene)
        }
        return thumbnailsDirectory.appendingPathComponent(thumbnailFilename, isDirectory: false)
    }

    func scene(withID id: UUID?) -> WallpaperScene? {
        guard let id else { return nil }
        return scenes.first { $0.id == id }
    }

    var favorites: WallpaperSceneCollection {
        if let existing = collections.first(where: { $0.kind == .favorites }) {
            return existing
        }
        return WallpaperSceneCollection(title: "Favorites", kind: .favorites)
    }

    #if DEBUG
    func prepareUITestFixtures() throws {
        guard AppRuntime.isUITest else { return }

        try? fileManager.removeItem(at: rootDirectory)
        prepareStorage()
        scenes.removeAll()
        collections.removeAll()

        let fixtures: [(String, NSColor)] = [
            ("Aurora Test", .systemIndigo),
            ("Forest Test", .systemGreen),
            ("Sunset Test", .systemOrange),
        ]

        for (index, fixture) in fixtures.enumerated() {
            let id = UUID()
            let filename = "ui-test-\(index).png"
            let destination = assetsDirectory.appendingPathComponent(filename)
            guard let data = Self.uiTestImageData(color: fixture.1) else {
                throw WallpaperSceneLibraryError.unreadableAsset
            }
            try data.write(to: destination, options: .atomic)
            scenes.append(
                WallpaperScene(
                    id: id,
                    title: fixture.0,
                    author: "MacFlow UI Tests",
                    kind: .image,
                    assetFilename: filename
                )
            )
        }

        ensureFavoritesCollection()
        try persistIndex()
    }
    #endif

    func isFavorite(_ scene: WallpaperScene) -> Bool {
        favorites.sceneIDs.contains(scene.id)
    }

    func contains(_ scene: WallpaperScene, in collection: WallpaperSceneCollection) -> Bool {
        collections
            .first(where: { $0.id == collection.id })?
            .sceneIDs
            .contains(scene.id) == true
    }

    func scenes(in collection: WallpaperSceneCollection) -> [WallpaperScene] {
        let membership = Set(collection.sceneIDs)
        return scenes.filter { membership.contains($0.id) }
    }

    func toggleFavorite(_ scene: WallpaperScene) {
        guard let index = collections.firstIndex(where: { $0.kind == .favorites }) else { return }
        toggleSceneID(scene.id, inCollectionAt: index)
    }

    func toggle(_ scene: WallpaperScene, in collection: WallpaperSceneCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        toggleSceneID(scene.id, inCollectionAt: index)
    }

    @discardableResult
    func createCollection(named proposedTitle: String) -> WallpaperSceneCollection? {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let collection = WallpaperSceneCollection(title: title)
        collections.append(collection)
        try? persistIndex()
        return collection
    }

    func remove(_ collection: WallpaperSceneCollection) {
        guard collection.kind == .custom else { return }
        collections.removeAll { $0.id == collection.id }
        try? persistIndex()
    }

    @discardableResult
    func importScene(from sourceURL: URL) async throws -> WallpaperScene {
        if sourceURL.pathExtension.lowercased() == WallpaperScenePackageSecurity.packageExtension {
            return try await importPackagedScene(from: sourceURL)
        }
        return try await importAsset(from: sourceURL)
    }

    private func importAsset(
        from sourceURL: URL,
        title explicitTitle: String? = nil,
        author explicitAuthor: String? = nil,
        rendering: WallpaperSceneRenderingConfiguration = .default
    ) async throws -> WallpaperScene {
        guard let kind = WallpaperSceneFileSupport.kind(for: sourceURL) else {
            throw WallpaperSceneLibraryError.unsupportedFormat
        }

        let accessedSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let id = UUID()
        let fileExtension = sourceURL.pathExtension.lowercased()
        let filename = "\(id.uuidString).\(fileExtension)"
        let destinationURL = assetsDirectory.appendingPathComponent(filename)
        let thumbnailFilename = kind == .video ? "\(id.uuidString).jpg" : nil
        let thumbnailURL = thumbnailFilename.map {
            thumbnailsDirectory.appendingPathComponent($0, isDirectory: false)
        }

        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            guard fileManager.isReadableFile(atPath: sourceURL.path) else {
                throw WallpaperSceneLibraryError.unreadableAsset
            }

            let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard byteCount <= WallpaperSceneFileSupport.maximumAssetBytes else {
                throw WallpaperSceneLibraryError.assetTooLarge
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            if let thumbnailURL {
                try? await Self.generateVideoThumbnail(from: destinationURL, at: thumbnailURL)
            }
        }.value

        let rawTitle = (explicitTitle ?? sourceURL.deletingPathExtension().lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAuthor = (explicitAuthor ?? "You")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scene = WallpaperScene(
            id: id,
            title: rawTitle.isEmpty ? "Untitled Scene" : rawTitle,
            author: rawAuthor.isEmpty ? "Unknown creator" : rawAuthor,
            kind: kind,
            assetFilename: filename,
            thumbnailFilename: thumbnailURL.flatMap {
                fileManager.fileExists(atPath: $0.path) ? thumbnailFilename : nil
            },
            rendering: rendering
        )
        scenes.insert(scene, at: 0)
        try persistIndex()
        return scene
    }

    func exportPackage(_ scene: WallpaperScene, to destinationURL: URL) async throws {
        guard libraryContains(scene) else {
            throw WallpaperSceneLibraryError.sceneNotFound
        }

        let accessedSecurityScope = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceAssetURL = assetURL(for: scene)
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw WallpaperScenePackageError.destinationExists
            }

            let temporaryURL = fileManager.temporaryDirectory
                .appendingPathComponent("NotchLandExport-\(UUID().uuidString)", isDirectory: true)
                .appendingPathExtension(WallpaperScenePackageSecurity.packageExtension)
            defer { try? fileManager.removeItem(at: temporaryURL) }

            try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
            let assetFilename = "asset.\(sourceAssetURL.pathExtension.lowercased())"
            let packagedAssetURL = temporaryURL.appendingPathComponent(assetFilename)
            try fileManager.copyItem(at: sourceAssetURL, to: packagedAssetURL)

            let manifest = WallpaperScenePackageManifest(
                title: WallpaperScenePackageSecurity.normalizedMetadata(
                    scene.title,
                    maximumLength: WallpaperScenePackageSecurity.maximumTitleLength,
                    fallback: "Untitled Scene"
                ),
                author: WallpaperScenePackageSecurity.normalizedMetadata(
                    scene.author,
                    maximumLength: WallpaperScenePackageSecurity.maximumAuthorLength,
                    fallback: "Unknown creator"
                ),
                kind: scene.kind,
                assetFilename: assetFilename,
                assetSHA256: try WallpaperScenePackageSecurity.sha256(of: packagedAssetURL),
                createdAt: scene.createdAt,
                rendering: scene.rendering
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: temporaryURL.appendingPathComponent(WallpaperScenePackageManifest.filename),
                options: .atomic
            )

            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }.value
    }

    private func importPackagedScene(from packageURL: URL) async throws -> WallpaperScene {
        let accessedSecurityScope = packageURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                packageURL.stopAccessingSecurityScopedResource()
            }
        }

        let validated = try await Task.detached(priority: .userInitiated) {
            try Self.validatePackage(at: packageURL)
        }.value
        return try await importAsset(
            from: validated.assetURL,
            title: validated.manifest.title,
            author: validated.manifest.author,
            rendering: validated.manifest.rendering ?? .default
        )
    }

    func updateRendering(
        forSceneID sceneID: UUID,
        configuration: WallpaperSceneRenderingConfiguration,
        persistsImmediately: Bool = true
    ) throws {
        guard let index = scenes.firstIndex(where: { $0.id == sceneID }) else {
            throw WallpaperSceneLibraryError.sceneNotFound
        }
        scenes[index].rendering = configuration.normalized
        if persistsImmediately {
            try persistIndex()
        }
    }

    func persistRenderingChanges() throws {
        try persistIndex()
    }

    func remove(_ scene: WallpaperScene) throws {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else {
            throw WallpaperSceneLibraryError.sceneNotFound
        }

        let assetURL = assetURL(for: scene)
        if fileManager.fileExists(atPath: assetURL.path) {
            try fileManager.removeItem(at: assetURL)
        }
        let previewURL = previewURL(for: scene)
        if previewURL != assetURL, fileManager.fileExists(atPath: previewURL.path) {
            try fileManager.removeItem(at: previewURL)
        }
        scenes.remove(at: index)
        for collectionIndex in collections.indices {
            collections[collectionIndex].sceneIDs.removeAll { $0 == scene.id }
        }
        try persistIndex()
    }

    func rename(_ scene: WallpaperScene, to proposedTitle: String) throws {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else {
            throw WallpaperSceneLibraryError.sceneNotFound
        }
        let trimmed = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        scenes[index].title = trimmed
        try persistIndex()
    }

    private func prepareStorage() {
        do {
            try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("NotchLand Scenes could not prepare storage: \(error.localizedDescription)")
        }
    }

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let index = try decoder.decode(SceneIndex.self, from: data)
            scenes = index.scenes.filter { scene in
                scene.manifestVersion <= WallpaperScene.manifestVersion
                    && fileManager.fileExists(atPath: assetURL(for: scene).path)
            }
            let availableSceneIDs = Set(scenes.map(\.id))
            collections = (index.collections ?? []).map { collection in
                var sanitized = collection
                sanitized.sceneIDs = collection.sceneIDs.filter { availableSceneIDs.contains($0) }
                return sanitized
            }
        } catch {
            NSLog("NotchLand Scenes could not load its library: \(error.localizedDescription)")
        }
    }

    private func persistIndex() throws {
        let index = SceneIndex(
            version: WallpaperScene.manifestVersion,
            scenes: scenes,
            collections: collections
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private func ensureFavoritesCollection() {
        guard !collections.contains(where: { $0.kind == .favorites }) else { return }
        collections.insert(
            WallpaperSceneCollection(title: "Favorites", kind: .favorites),
            at: 0
        )
        try? persistIndex()
    }

    private func toggleSceneID(_ sceneID: UUID, inCollectionAt index: Int) {
        if let membershipIndex = collections[index].sceneIDs.firstIndex(of: sceneID) {
            collections[index].sceneIDs.remove(at: membershipIndex)
        } else {
            collections[index].sceneIDs.append(sceneID)
        }
        try? persistIndex()
    }

    private func libraryContains(_ scene: WallpaperScene) -> Bool {
        scenes.contains { $0.id == scene.id }
    }

    private nonisolated static func validatePackage(
        at packageURL: URL
    ) throws -> (manifest: WallpaperScenePackageManifest, assetURL: URL) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WallpaperScenePackageError.invalidPackage
        }

        let packageValues = try packageURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard packageValues.isSymbolicLink != true else {
            throw WallpaperScenePackageError.invalidPackage
        }

        let packageContents = try fileManager.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        guard packageContents.count == 2,
              packageContents.contains(where: {
                  $0.lastPathComponent == WallpaperScenePackageManifest.filename
              }) else {
            throw WallpaperScenePackageError.invalidPackage
        }

        let manifestURL = packageURL.appendingPathComponent(
            WallpaperScenePackageManifest.filename,
            isDirectory: false
        )
        let manifestValues = try manifestURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard fileManager.isReadableFile(atPath: manifestURL.path),
              manifestValues.isRegularFile == true,
              manifestValues.isSymbolicLink != true,
              let manifestSize = manifestValues.fileSize,
              manifestSize > 0,
              manifestSize <= WallpaperScenePackageSecurity.maximumManifestBytes else {
            throw WallpaperScenePackageError.invalidPackage
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: WallpaperScenePackageManifest
        do {
            manifest = try decoder.decode(
                WallpaperScenePackageManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw WallpaperScenePackageError.invalidPackage
        }
        guard manifest.formatVersion >= 1 else {
            throw WallpaperScenePackageError.invalidPackage
        }
        guard manifest.formatVersion <= WallpaperScenePackageManifest.currentVersion else {
            throw WallpaperScenePackageError.unsupportedVersion
        }
        guard WallpaperScenePackageSecurity.isSafeFilename(manifest.assetFilename) else {
            throw WallpaperScenePackageError.unsafePath
        }

        let assetURL = packageURL.appendingPathComponent(
            manifest.assetFilename,
            isDirectory: false
        )
        let values = try assetURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              Int64(fileSize) <= WallpaperSceneFileSupport.maximumAssetBytes,
              packageContents.contains(where: { $0.lastPathComponent == manifest.assetFilename }),
              WallpaperSceneFileSupport.kind(for: assetURL) == manifest.kind else {
            throw WallpaperScenePackageError.invalidAsset
        }
        let normalizedTitle = WallpaperScenePackageSecurity.normalizedMetadata(
            manifest.title,
            maximumLength: WallpaperScenePackageSecurity.maximumTitleLength,
            fallback: ""
        )
        let normalizedAuthor = WallpaperScenePackageSecurity.normalizedMetadata(
            manifest.author,
            maximumLength: WallpaperScenePackageSecurity.maximumAuthorLength,
            fallback: ""
        )
        guard !normalizedTitle.isEmpty,
              !normalizedAuthor.isEmpty,
              normalizedTitle == manifest.title,
              normalizedAuthor == manifest.author else {
            throw WallpaperScenePackageError.invalidPackage
        }
        guard try WallpaperScenePackageSecurity.sha256(of: assetURL) == manifest.assetSHA256 else {
            throw WallpaperScenePackageError.checksumMismatch
        }
        return (manifest, assetURL)
    }

    private nonisolated static func generateVideoThumbnail(from sourceURL: URL, at destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)
        let (image, _) = try await generator.image(
            at: CMTime(seconds: 0.25, preferredTimescale: 600)
        )
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.82]
        ) else { return }
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
    }

    #if DEBUG
    private static func uiTestImageData(color: NSColor) -> Data? {
        let size = NSSize(width: 96, height: 60)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
        guard let tiffData = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }
    #endif
}
