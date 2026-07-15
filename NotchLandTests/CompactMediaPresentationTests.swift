//
//  CompactMediaPresentationTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct CompactMediaPresentationTests {
    @Test func appleTVUsesOneSourceIdentityAndEpisodeHierarchy() {
        var track = makeTrack(
            title: "Děsivé zázraky",
            artist: "Monarch: Odkaz monster",
            album: "Season 1 · Episode 6",
            application: "TV",
            bundle: "com.apple.TV"
        )
        track.seriesTitle = "Monarch: Odkaz monster"
        track.episodeTitle = "Děsivé zázraky"
        track.seasonNumber = 1
        track.episodeNumber = 6

        let presentation = track.compactPresentation
        #expect(presentation.source.id == .appleTV)
        #expect(presentation.source.sourceMark == .appleTV)
        #expect(presentation.source.applicationBundleIdentifier == "com.apple.TV")
        #expect(presentation.primaryTitle == "Děsivé zázraky")
        #expect(presentation.secondaryTitle == "S1 · E6")
        #expect(presentation.mediaKind == .video)
        #expect(presentation.preferredWidth == 540)
    }

    @Test func spotifyUsesSongAndArtistWithoutAlbumClutter() {
        let track = makeTrack(
            title: "Instant Crush",
            artist: "Daft Punk",
            album: "Random Access Memories",
            application: "Spotify",
            bundle: "com.spotify.client"
        )

        let presentation = track.compactPresentation
        #expect(presentation.source.id == .spotify)
        #expect(presentation.source.sourceMark == .spotify)
        #expect(presentation.primaryTitle == "Instant Crush")
        #expect(presentation.secondaryTitle == "Daft Punk")
        #expect(presentation.mediaKind == .audio)
    }

    @Test func netflixUsesNetflixMarkAndVideoMetadata() {
        var track = makeTrack(
            title: "The We We Are",
            artist: "Severance",
            album: "Season 1, Episode 9",
            application: "Safari",
            bundle: "com.apple.Safari"
        )
        track.contentIdentifier = "https://www.netflix.com/watch/81234567"
        track.seriesTitle = "Severance"
        track.episodeTitle = "The We We Are"
        track.seasonNumber = 1
        track.episodeNumber = 9

        let presentation = track.compactPresentation
        #expect(presentation.source.id == .netflix)
        #expect(presentation.source.sourceMark == .netflix)
        #expect(presentation.source.applicationBundleIdentifier == nil)
        #expect(presentation.primaryTitle == "The We We Are")
        #expect(presentation.secondaryTitle == "S1 · E9")
    }

    @Test func appleMusicUsesSongAndArtist() {
        let track = makeTrack(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            application: "Music",
            bundle: "com.apple.Music"
        )

        let presentation = track.compactPresentation
        #expect(presentation.source.id == .appleMusic)
        #expect(presentation.source.sourceMark == .appleMusic)
        #expect(presentation.primaryTitle == "Midnight City")
        #expect(presentation.secondaryTitle == "M83")
    }

    @Test func youtubeUsesVideoTitleAndChannel() {
        var track = makeTrack(
            title: "Inside Apple Park",
            artist: "Apple",
            album: nil,
            application: "Safari",
            bundle: "com.apple.Safari"
        )
        track.serviceIdentifier = "com.google.youtube"

        let presentation = track.compactPresentation
        #expect(presentation.source.id == .youtube)
        #expect(presentation.source.sourceMark == .youtube)
        #expect(presentation.primaryTitle == "Inside Apple Park")
        #expect(presentation.secondaryTitle == "Apple")
        #expect(presentation.preferredWidth == 550)
    }

    @Test func unknownSourceUsesExactlyOneFallbackMark() {
        let track = makeTrack(
            title: "Local recording",
            artist: "Studio",
            album: nil,
            application: "IINA",
            bundle: "com.colliderli.iina"
        )

        let presentation = track.compactPresentation
        #expect(presentation.source.id == .other)
        #expect(presentation.source.sourceMark == .system("play.fill"))
        #expect(presentation.primaryTitle == "Local recording")
        #expect(presentation.secondaryTitle == "Studio")
    }

    @Test func disneyPlusUsesDedicatedVideoIdentity() {
        var track = makeTrack(
            title: "Chapter One",
            artist: "Andor",
            album: "S1 · E1",
            application: "Safari",
            bundle: "com.apple.Safari"
        )
        track.contentIdentifier = "https://www.disneyplus.com/video/example"
        #expect(track.mediaSource == .disneyPlus)
        #expect(track.compactPresentation.source.sourceMark == .disneyPlus)
        #expect(track.compactPresentation.mediaKind == .video)
    }

    @Test func appleTVSearchParserFindsExactEpisodeAndArtwork() {
        let searchHTML = #"""
        <script>{"ariaLabel":"Nechť se přihlásí skutečná May","contextAction":{"url":"https://tv.apple.com/cz/episode/necht-se-prihlasi-skutecna-may/umc.cmc.episode?showId=umc.cmc.show"},"artwork":{}}</script>
        """#
        let pageURL = AppleTVArtworkHTMLParser.pageURL(
            in: searchHTML,
            title: "Nechť se přihlásí skutečná May"
        )
        #expect(pageURL?.host == "tv.apple.com")
        #expect(pageURL?.path.contains("/episode/") == true)

        let pageHTML = #"""
        <meta property="og:image" content="https://is1-ssl.mzstatic.com/image/thumb/example/1200x675.jpg">
        """#
        let artworkURL = AppleTVArtworkHTMLParser.openGraphArtworkURL(in: pageHTML)
        #expect(artworkURL?.host == "is1-ssl.mzstatic.com")
        #expect(artworkURL?.lastPathComponent == "1200x675.jpg")
    }

    private func makeTrack(
        title: String,
        artist: String,
        album: String?,
        application: String,
        bundle: String
    ) -> NowPlayingService.Track {
        NowPlayingService.Track(
            title: title,
            artist: artist,
            album: album,
            artwork: nil,
            duration: 240,
            elapsedAtTimestamp: 40,
            timestamp: Date(),
            playbackRate: 1,
            sourceApplicationName: application,
            sourceBundleIdentifier: bundle
        )
    }
}
