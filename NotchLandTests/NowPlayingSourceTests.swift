//
//  NowPlayingSourceTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

struct NowPlayingSourceTests {
    @Test func classifiesAppleMusicFromBundleIdentifier() {
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: "com.apple.Music",
                applicationName: nil
            ) == .appleMusic
        )
    }

    @Test func classifiesSpotifyFromBundleOrApplicationName() {
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: "com.spotify.client",
                applicationName: nil
            ) == .spotify
        )
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: nil,
                applicationName: "Spotify"
            ) == .spotify
        )
    }

    @Test func classifiesAppleTVWithoutConfusingGenericVideoApps() {
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: "com.apple.TV",
                applicationName: "TV"
            ) == .appleTV
        )
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: "com.example.video",
                applicationName: "Video Player"
            ) == .other
        )
    }

    @Test func identifiesStreamingServiceBehindBrowserPlayback() {
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: "com.apple.Safari",
                applicationName: "Safari",
                serviceIdentifier: "com.google.youtube",
                contentIdentifier: nil
            ) == .youtube
        )
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: "com.google.Chrome",
                applicationName: "Google Chrome",
                serviceIdentifier: nil,
                contentIdentifier: "https://www.netflix.com/watch/81234567"
            ) == .netflix
        )
    }

    @Test func unknownAndEmptySourcesUseGenericTheme() {
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: nil,
                applicationName: nil
            ) == .other
        )
        #expect(
            NowPlayingService.mediaSource(
                bundleIdentifier: "com.apple.podcasts",
                applicationName: "Podcasts"
            ) == .other
        )
    }

    @MainActor
    @Test func appleTVUsesExplicitEpisodeMetadata() {
        var track = appleTVTrack(
            title: "The Heist",
            artist: "Monarch",
            album: "Season 2"
        )
        track.seriesTitle = "Monarch: Legacy of Monsters"
        track.episodeTitle = "The Heist"
        track.seasonNumber = 2
        track.episodeNumber = 7
        track.genre = "Drama"

        let presentation = track.videoPresentation
        #expect(presentation?.title == "Monarch: Legacy of Monsters")
        #expect(presentation?.subtitle == "The Heist")
        #expect(presentation?.episodeLabel == "S2 · E7")
        #expect(presentation?.genre == "Drama")
        #expect(presentation?.isEpisode == true)
    }

    @MainActor
    @Test func appleTVDerivesEpisodeMetadataFromStandardNowPlayingFields() {
        let track = appleTVTrack(
            title: "Tajemství a lži",
            artist: "Monarch: Odkaz monster",
            album: "Série 2 · Epizoda 7"
        )

        let presentation = track.videoPresentation
        #expect(presentation?.title == "Monarch: Odkaz monster")
        #expect(presentation?.subtitle == "Tajemství a lži")
        #expect(presentation?.seasonNumber == 2)
        #expect(presentation?.episodeNumber == 7)
        #expect(presentation?.episodeLabel == "S2 · E7")
    }

    @MainActor
    @Test func appleTVMovieDoesNotInventEpisodeMetadata() {
        let track = appleTVTrack(
            title: "Killers of the Flower Moon",
            artist: "Apple Original Films",
            album: nil
        )

        let presentation = track.videoPresentation
        #expect(presentation?.title == "Killers of the Flower Moon")
        #expect(presentation?.subtitle == "Apple Original Films")
        #expect(presentation?.episodeLabel == nil)
        #expect(presentation?.isEpisode == false)
    }

    @MainActor
    @Test func appleTVParsesCzechOrdinalSeasonAndEpisodeFormat() {
        let track = appleTVTrack(
            title: "Návrat",
            artist: "Příběh rodu",
            album: "2. série, 7. díl"
        )

        let presentation = track.videoPresentation
        #expect(presentation?.episodeLabel == "S2 · E7")
        #expect(presentation?.title == "Příběh rodu")
        #expect(presentation?.subtitle == "Návrat")
    }

    @MainActor
    private func appleTVTrack(
        title: String,
        artist: String,
        album: String?
    ) -> NowPlayingService.Track {
        NowPlayingService.Track(
            title: title,
            artist: artist,
            album: album,
            artwork: nil,
            duration: 3_600,
            elapsedAtTimestamp: 600,
            timestamp: Date(),
            playbackRate: 1,
            sourceApplicationName: "TV",
            sourceBundleIdentifier: "com.apple.TV"
        )
    }
}
