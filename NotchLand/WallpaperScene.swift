//
//  WallpaperScene.swift
//  NotchLand
//
//  A versioned, non-executable manifest for a local NotchLand Scene.
//

import Foundation

nonisolated struct WallpaperSceneRenderingConfiguration: Codable, Hashable, Sendable {
    enum MotionPreset: String, Codable, CaseIterable, Identifiable, Sendable {
        case none
        case cinematicZoom
        case slowDrift

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "Still"
            case .cinematicZoom: "Cinematic Zoom"
            case .slowDrift: "Slow Drift"
            }
        }

        var detail: String {
            switch self {
            case .none: "No camera movement"
            case .cinematicZoom: "A subtle, focus-friendly push in"
            case .slowDrift: "A gentle pan with a shallow zoom"
            }
        }

        var systemImage: String {
            switch self {
            case .none: "pause.rectangle"
            case .cinematicZoom: "viewfinder"
            case .slowDrift: "move.3d"
            }
        }
    }

    enum AmbientEffect: String, Codable, CaseIterable, Identifiable, Sendable {
        case none
        case dust
        case snow
        case embers

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .dust: "Ambient Dust"
            case .snow: "Snowfall"
            case .embers: "Embers"
            }
        }

        var detail: String {
            switch self {
            case .none: "No atmospheric overlay"
            case .dust: "Slow, soft particles with minimal visual noise"
            case .snow: "A calm foreground snowfall layer"
            case .embers: "Warm particles rising from the lower edge"
            }
        }

        var systemImage: String {
            switch self {
            case .none: "circle.slash"
            case .dust: "sparkles"
            case .snow: "snowflake"
            case .embers: "flame.fill"
            }
        }
    }

    enum MusicReaction: String, Codable, CaseIterable, Identifiable, Sendable {
        case none
        case ambientGlow
        case playbackPulse

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: "Off"
            case .ambientGlow: "Ambient Glow"
            case .playbackPulse: "Playback Pulse"
            }
        }

        var detail: String {
            switch self {
            case .none: "The scene stays independent of media playback"
            case .ambientGlow: "A slow artwork-colored glow while media is playing"
            case .playbackPulse: "A more expressive compositor pulse for music sessions"
            }
        }

        var systemImage: String {
            switch self {
            case .none: "waveform.slash"
            case .ambientGlow: "waveform.path.ecg"
            case .playbackPulse: "waveform.badge.plus"
            }
        }
    }

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
    static let saturationRange: ClosedRange<Double> = 0...1.4
    static let contrastRange: ClosedRange<Double> = 0.8...1.25
    static let vignetteRange: ClosedRange<Double> = 0...0.65
    static let effectIntensityRange: ClosedRange<Double> = 0.1...1
    static let parallaxStrengthRange: ClosedRange<Double> = 0...1
    static let musicReactionIntensityRange: ClosedRange<Double> = 0.1...1
    static let `default` = WallpaperSceneRenderingConfiguration()

    var scalingMode: ScalingMode
    var playbackRate: Double
    var dimming: Double
    var motionPreset: MotionPreset
    var saturation: Double
    var contrast: Double
    var vignette: Double
    var ambientEffect: AmbientEffect
    var effectIntensity: Double
    var parallaxStrength: Double
    var musicReaction: MusicReaction
    var musicReactionIntensity: Double

    init(
        scalingMode: ScalingMode = .fill,
        playbackRate: Double = 1,
        dimming: Double = 0,
        motionPreset: MotionPreset = .none,
        saturation: Double = 1,
        contrast: Double = 1,
        vignette: Double = 0,
        ambientEffect: AmbientEffect = .none,
        effectIntensity: Double = 0.45,
        parallaxStrength: Double = 0,
        musicReaction: MusicReaction = .none,
        musicReactionIntensity: Double = 0.45
    ) {
        self.scalingMode = scalingMode
        self.playbackRate = playbackRate
        self.dimming = dimming
        self.motionPreset = motionPreset
        self.saturation = saturation
        self.contrast = contrast
        self.vignette = vignette
        self.ambientEffect = ambientEffect
        self.effectIntensity = effectIntensity
        self.parallaxStrength = parallaxStrength
        self.musicReaction = musicReaction
        self.musicReactionIntensity = musicReactionIntensity
    }

    var normalized: WallpaperSceneRenderingConfiguration {
        let closestRate = Self.playbackRateOptions.min {
            abs($0 - playbackRate) < abs($1 - playbackRate)
        } ?? 1
        return WallpaperSceneRenderingConfiguration(
            scalingMode: scalingMode,
            playbackRate: closestRate,
            dimming: Self.clamp(dimming, to: Self.dimmingRange),
            motionPreset: motionPreset,
            saturation: Self.clamp(saturation, to: Self.saturationRange),
            contrast: Self.clamp(contrast, to: Self.contrastRange),
            vignette: Self.clamp(vignette, to: Self.vignetteRange),
            ambientEffect: ambientEffect,
            effectIntensity: Self.clamp(effectIntensity, to: Self.effectIntensityRange),
            parallaxStrength: Self.clamp(parallaxStrength, to: Self.parallaxStrengthRange),
            musicReaction: musicReaction,
            musicReactionIntensity: Self.clamp(
                musicReactionIntensity,
                to: Self.musicReactionIntensityRange
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case scalingMode
        case playbackRate
        case dimming
        case motionPreset
        case saturation
        case contrast
        case vignette
        case ambientEffect
        case effectIntensity
        case parallaxStrength
        case musicReaction
        case musicReactionIntensity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scalingMode: try container.decodeIfPresent(ScalingMode.self, forKey: .scalingMode) ?? .fill,
            playbackRate: try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1,
            dimming: try container.decodeIfPresent(Double.self, forKey: .dimming) ?? 0,
            motionPreset: try container.decodeIfPresent(MotionPreset.self, forKey: .motionPreset) ?? .none,
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1,
            contrast: try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 1,
            vignette: try container.decodeIfPresent(Double.self, forKey: .vignette) ?? 0,
            ambientEffect: try container.decodeIfPresent(AmbientEffect.self, forKey: .ambientEffect) ?? .none,
            effectIntensity: try container.decodeIfPresent(Double.self, forKey: .effectIntensity) ?? 0.45,
            parallaxStrength: try container.decodeIfPresent(Double.self, forKey: .parallaxStrength) ?? 0,
            musicReaction: try container.decodeIfPresent(MusicReaction.self, forKey: .musicReaction) ?? .none,
            musicReactionIntensity: try container.decodeIfPresent(
                Double.self,
                forKey: .musicReactionIntensity
            ) ?? 0.45
        )
        self = normalized
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
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

    static let manifestVersion = 4

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
