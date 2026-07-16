//
//  WallpaperScene.swift
//  NotchLand
//
//  A versioned, non-executable manifest for a local NotchLand Scene.
//

import Foundation

nonisolated struct WallpaperSceneRenderingConfiguration: Codable, Hashable, Sendable {
    enum ScalingMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case fill
        case fit
        case stretch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fill: "Fill"
            case .fit: "Fit"
            case .stretch: "Stretch"
            }
        }

        var systemImage: String {
            switch self {
            case .fill: "arrow.up.left.and.arrow.down.right"
            case .fit: "arrow.down.right.and.arrow.up.left"
            case .stretch: "rectangle.inset.filled.and.person.filled"
            }
        }
    }

    static let playbackRateOptions: [Double] = [0.5, 0.75, 1, 1.25, 1.5]
    static let dimmingRange: ClosedRange<Double> = 0...0.7
    static let `default` = WallpaperSceneRenderingConfiguration()

    var scalingMode: ScalingMode
    var playbackRate: Double
    var dimming: Double

    init(
        scalingMode: ScalingMode = .fill,
        playbackRate: Double = 1,
        dimming: Double = 0
    ) {
        self.scalingMode = scalingMode
        self.playbackRate = playbackRate
        self.dimming = dimming
    }

    var normalized: WallpaperSceneRenderingConfiguration {
        let closestRate = Self.playbackRateOptions.min {
            abs($0 - playbackRate) < abs($1 - playbackRate)
        } ?? 1
        return WallpaperSceneRenderingConfiguration(
            scalingMode: scalingMode,
            playbackRate: closestRate,
            dimming: min(max(dimming, Self.dimmingRange.lowerBound), Self.dimmingRange.upperBound)
        )
    }
}

nonisolated struct WallpaperScene: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case image
        case video

        var displayName: String {
            switch self {
            case .image: "Still"
            case .video: "Video"
            }
        }

        var systemImage: String {
            switch self {
            case .image: "photo"
            case .video: "play.rectangle.fill"
            }
        }
    }

    static let manifestVersion = 2

    let id: UUID
    var title: String
    var author: String
    let kind: Kind
    let assetFilename: String
    let thumbnailFilename: String?
    let createdAt: Date
    let manifestVersion: Int
    var rendering: WallpaperSceneRenderingConfiguration

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "You",
        kind: Kind,
        assetFilename: String,
        thumbnailFilename: String? = nil,
        createdAt: Date = .now,
        manifestVersion: Int = WallpaperScene.manifestVersion,
        rendering: WallpaperSceneRenderingConfiguration = .default
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.kind = kind
        self.assetFilename = assetFilename
        self.thumbnailFilename = thumbnailFilename
        self.createdAt = createdAt
        self.manifestVersion = manifestVersion
        self.rendering = rendering.normalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case kind
        case assetFilename
        case thumbnailFilename
        case createdAt
        case manifestVersion
        case rendering
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        kind = try container.decode(Kind.self, forKey: .kind)
        assetFilename = try container.decode(String.self, forKey: .assetFilename)
        thumbnailFilename = try container.decodeIfPresent(String.self, forKey: .thumbnailFilename)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        rendering = try container.decodeIfPresent(
            WallpaperSceneRenderingConfiguration.self,
            forKey: .rendering
        )?.normalized ?? .default
    }
}

nonisolated enum WallpaperSceneFileSupport {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    static let maximumAssetBytes: Int64 = 2 * 1_024 * 1_024 * 1_024

    static func isSupportedImport(_ url: URL) -> Bool {
        kind(for: url) != nil
            || url.pathExtension.lowercased() == WallpaperScenePackageSecurity.packageExtension
    }

    static func kind(for url: URL) -> WallpaperScene.Kind? {
        let fileExtension = url.pathExtension.lowercased()
        if imageExtensions.contains(fileExtension) { return .image }
        if videoExtensions.contains(fileExtension) { return .video }
        return nil
    }
}

enum WallpaperPerformanceProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case eco
    case balanced
    case cinematic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .eco: "Eco"
        case .balanced: "Balanced"
        case .cinematic: "Cinematic"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Adapts to power and temperature"
        case .eco: "24 FPS · reduced energy"
        case .balanced: "30 FPS · recommended"
        case .cinematic: "60 FPS · maximum quality"
        }
    }

    var targetFramesPerSecond: Int {
        switch self {
        case .automatic, .balanced: 30
        case .eco: 24
        case .cinematic: 60
        }
    }
}
