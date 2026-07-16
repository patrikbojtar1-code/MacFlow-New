//
//  WallpaperScenePackage.swift
//  NotchLand
//
//  A data-only, checksummed package format for sharing Scenes safely.
//

import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let notchLandScene = UTType(
        exportedAs: "com.rudrashah.notchland.scene",
        conformingTo: .package
    )
}

nonisolated struct WallpaperScenePackageManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let filename = "manifest.json"

    let formatVersion: Int
    let title: String
    let author: String
    let kind: WallpaperScene.Kind
    let assetFilename: String
    let assetSHA256: String
    let createdAt: Date
    let rendering: WallpaperSceneRenderingConfiguration?

    init(
        formatVersion: Int = currentVersion,
        title: String,
        author: String,
        kind: WallpaperScene.Kind,
        assetFilename: String,
        assetSHA256: String,
        createdAt: Date = .now,
        rendering: WallpaperSceneRenderingConfiguration? = nil
    ) {
        self.formatVersion = formatVersion
        self.title = title
        self.author = author
        self.kind = kind
        self.assetFilename = assetFilename
        self.assetSHA256 = assetSHA256
        self.createdAt = createdAt
        self.rendering = rendering?.normalized
    }
}

enum WallpaperScenePackageError: LocalizedError, Equatable {
    case invalidPackage
    case unsupportedVersion
    case unsafePath
    case invalidAsset
    case checksumMismatch
    case destinationExists

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "This NotchLand Scene package is incomplete or damaged."
        case .unsupportedVersion:
            "This Scene was created by a newer version of NotchLand."
        case .unsafePath:
            "The Scene package contains an unsafe file path."
        case .invalidAsset:
            "The packaged wallpaper asset is missing or unsupported."
        case .checksumMismatch:
            "The Scene asset does not match its recorded manifest checksum."
        case .destinationExists:
            "A Scene package with this name already exists at that location."
        }
    }
}

nonisolated enum WallpaperScenePackageSecurity {
    static let packageExtension = "notchscene"
    static let hashingChunkSize = 1_048_576
    static let maximumManifestBytes = 128 * 1_024
    static let maximumTitleLength = 160
    static let maximumAuthorLength = 80

    static func isSafeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && !filename.contains("..")
            && !filename.contains("/")
            && !filename.contains("\\")
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data: Data? = try autoreleasepool {
                try handle.read(upToCount: hashingChunkSize)
            }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedMetadata(
        _ value: String,
        maximumLength: Int,
        fallback: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(maximumLength))
    }
}
