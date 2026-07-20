//
//  CompactMediaSnapshotTests.swift
//  NotchLandTests
//

import AppKit
import SwiftUI
import Testing
@testable import NotchLand

@MainActor
struct CompactMediaSnapshotTests {
    @Test func capturesFiveCompactSourceLayouts() throws {
        let outputDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/CompactMediaScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        for fixture in fixtures {
            for size in NotchSize.allCases {
                let presentation = fixture.track.compactPresentation
                let bodySize = NotchLayoutMetrics.bodySize(for: size)
                let invertedRadius = FloatingNotchView.musicInvertedRadius
                let shape = NotchDropShape(
                    invertedCornerRadius: invertedRadius,
                    bottomCornerRadius: NotchLayoutMetrics.bottomRadius(for: size)
                )
                let content = ZStack(alignment: .bottom) {
                    shape.fill(Color.black)
                    CompactMediaContent(
                        presentation: presentation,
                        processedBackground: fixture.background,
                        backgroundIdentity: fixture.name,
                        hardwareNotchWidth: 184,
                        notchSize: size,
                        isHovering: false,
                        revealsContent: true,
                        accessibilityContrast: .standard,
                        reduceMotion: true,
                        onPlayPause: {}
                    )
                    .frame(width: bodySize.width, height: bodySize.height)
                }
                .frame(width: bodySize.width + invertedRadius * 2, height: bodySize.height)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.38), radius: 10, y: 6)
                .padding(18)

                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    Issue.record("Could not render compact snapshot for \(fixture.name)-\(size.rawValue)")
                    continue
                }

                let destination = outputDirectory.appendingPathComponent("\(fixture.name)-\(size.rawValue).png")
                try png.write(to: destination, options: .atomic)
                #expect(FileManager.default.fileExists(atPath: destination.path))
            }
        }
    }

    @Test func capturesIntegratedGestureEdgeBubbles() throws {
        let outputDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/CompactMediaScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let fixture = fixtures.first { $0.name == "spotify" }!
        let size = NotchSize.medium
        let bodySize = NotchLayoutMetrics.bodySize(for: size)
        let invertedRadius = FloatingNotchView.musicInvertedRadius
        let shape = NotchDropShape(
            invertedCornerRadius: invertedRadius,
            bottomCornerRadius: NotchLayoutMetrics.bottomRadius(for: size)
        )

        for (name, progress) in [
            ("gesture-next-025", CGFloat(0.25)),
            ("gesture-next-050", CGFloat(0.50)),
            ("gesture-next-075", CGFloat(0.75)),
            ("gesture-next-right", CGFloat(1)),
            ("gesture-previous-left", CGFloat(-1)),
        ] {
            let content = ZStack(alignment: .bottom) {
                shape.fill(Color.black)
                CompactMediaContent(
                    presentation: fixture.track.compactPresentation,
                    processedBackground: fixture.background,
                    backgroundIdentity: name,
                    hardwareNotchWidth: 184,
                    notchSize: size,
                    isHovering: true,
                    revealsContent: true,
                    accessibilityContrast: .standard,
                    reduceMotion: true,
                    gestureProgress: progress,
                    onPlayPause: {}
                )
                .frame(width: bodySize.width, height: bodySize.height)
            }
            .frame(width: bodySize.width + invertedRadius * 2, height: bodySize.height)
            .clipShape(shape)
            .padding(18)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                Issue.record("Could not render compact gesture snapshot for \(name)")
                continue
            }

            let destination = outputDirectory.appendingPathComponent("\(name).png")
            try png.write(to: destination, options: .atomic)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test func capturesOriginalAndAmbientMediaSurfaces() throws {
        let outputDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/CompactMediaScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let fixture = fixtures.first { $0.name == "spotify" }!
        let size = NotchSize.medium
        let bodySize = NotchLayoutMetrics.bodySize(for: size)
        let invertedRadius = FloatingNotchView.musicInvertedRadius
        let shape = NotchDropShape(
            invertedCornerRadius: invertedRadius,
            bottomCornerRadius: NotchLayoutMetrics.bottomRadius(for: size)
        )

        for appearance in NotchSettings.MediaAppearance.allCases {
            let content = ZStack(alignment: .bottom) {
                shape.fill(Color.black)
                CompactMediaContent(
                    presentation: fixture.track.compactPresentation,
                    processedBackground: fixture.background,
                    backgroundIdentity: "media-surface-\(appearance.rawValue)",
                    hardwareNotchWidth: 184,
                    notchSize: size,
                    isHovering: false,
                    revealsContent: true,
                    accessibilityContrast: .standard,
                    reduceMotion: true,
                    mediaAppearance: appearance,
                    onPlayPause: {}
                )
                .frame(width: bodySize.width, height: bodySize.height)
            }
            .frame(width: bodySize.width + invertedRadius * 2, height: bodySize.height)
            .clipShape(shape)
            .padding(18)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                Issue.record("Could not render \(appearance.rawValue) media surface")
                continue
            }

            let destination = outputDirectory
                .appendingPathComponent("media-surface-\(appearance.rawValue).png")
            try png.write(to: destination, options: .atomic)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private var fixtures: [(name: String, track: NowPlayingService.Track, background: NSImage)] {
        [
            (
                "apple-tv",
                videoTrack(
                    source: .appleTV,
                    title: "Děsivé zázraky",
                    show: "Monarch: Odkaz monster",
                    season: 1,
                    episode: 6
                ),
                background(colors: [
                    NSColor(red: 0.34, green: 0.28, blue: 0.12, alpha: 1),
                    NSColor(red: 0.08, green: 0.11, blue: 0.09, alpha: 1),
                ])
            ),
            (
                "spotify",
                audioTrack(
                    title: "Instant Crush",
                    artist: "Daft Punk",
                    application: "Spotify",
                    bundle: "com.spotify.client"
                ),
                background(colors: [
                    NSColor(red: 0.07, green: 0.30, blue: 0.18, alpha: 1),
                    NSColor(red: 0.06, green: 0.07, blue: 0.07, alpha: 1),
                ])
            ),
            (
                "netflix",
                videoTrack(
                    source: .netflix,
                    title: "The We We Are",
                    show: "Severance",
                    season: 1,
                    episode: 9
                ),
                background(colors: [
                    NSColor(red: 0.34, green: 0.05, blue: 0.06, alpha: 1),
                    NSColor(red: 0.08, green: 0.05, blue: 0.05, alpha: 1),
                ])
            ),
            (
                "apple-music",
                audioTrack(
                    title: "Midnight City",
                    artist: "M83",
                    application: "Music",
                    bundle: "com.apple.Music"
                ),
                background(colors: [
                    NSColor(red: 0.46, green: 0.10, blue: 0.30, alpha: 1),
                    NSColor(red: 0.08, green: 0.08, blue: 0.18, alpha: 1),
                ])
            ),
            (
                "youtube",
                youtubeTrack,
                background(colors: [
                    NSColor(red: 0.40, green: 0.08, blue: 0.05, alpha: 1),
                    NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                ])
            ),
        ]
    }

    private func audioTrack(
        title: String,
        artist: String,
        application: String,
        bundle: String
    ) -> NowPlayingService.Track {
        NowPlayingService.Track(
            title: title,
            artist: artist,
            album: "Album",
            artwork: nil,
            duration: 240,
            elapsedAtTimestamp: 64,
            timestamp: Date(),
            playbackRate: 1,
            sourceApplicationName: application,
            sourceBundleIdentifier: bundle
        )
    }

    private func videoTrack(
        source: NowPlayingService.MediaSource,
        title: String,
        show: String,
        season: Int,
        episode: Int
    ) -> NowPlayingService.Track {
        var track = NowPlayingService.Track(
            title: title,
            artist: show,
            album: "Season \(season) · Episode \(episode)",
            artwork: nil,
            duration: 3_100,
            elapsedAtTimestamp: 740,
            timestamp: Date(),
            playbackRate: 1,
            sourceApplicationName: source == .appleTV ? "TV" : "Safari",
            sourceBundleIdentifier: source == .appleTV ? "com.apple.TV" : "com.apple.Safari"
        )
        track.seriesTitle = show
        track.episodeTitle = title
        track.seasonNumber = season
        track.episodeNumber = episode
        if source == .netflix {
            track.contentIdentifier = "https://www.netflix.com/watch/81234567"
        }
        return track
    }

    private var youtubeTrack: NowPlayingService.Track {
        var track = NowPlayingService.Track(
            title: "Inside Apple Park",
            artist: "Apple",
            album: nil,
            artwork: nil,
            duration: 620,
            elapsedAtTimestamp: 90,
            timestamp: Date(),
            playbackRate: 0,
            sourceApplicationName: "Safari",
            sourceBundleIdentifier: "com.apple.Safari"
        )
        track.serviceIdentifier = "com.google.youtube"
        return track
    }

    private func background(colors: [NSColor]) -> NSImage {
        NSImage(size: NSSize(width: 760, height: 96), flipped: false) { rect in
            NSGradient(colors: colors)?.draw(in: rect, angle: 0)
            return true
        }
    }
}
