//
//  NowPlayingService.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Observable wrapper around MediaRemote. Tracks the current "Now Playing"
//  item across the system (Music, Spotify, Safari, Chrome, Podcasts, …) and
//  publishes a normalized `Track` that the UI can render.
//
//  All MediaRemote IPC is proxied through `MediaRemoteHelper`, an
//  Apple-signed swift subprocess — see that file for the why.
//

import AppKit
import Combine
import Foundation

@MainActor
final class NowPlayingService: ObservableObject {
    enum MediaSource: String, Equatable, Sendable {
        case appleMusic
        case spotify
        case appleTV
        case youtube
        case netflix
        case disneyPlus
        case other

        var isVideo: Bool {
            switch self {
            case .appleTV, .youtube, .netflix, .disneyPlus: true
            case .appleMusic, .spotify, .other: false
            }
        }
    }

    enum CompactMediaKind: Equatable, Sendable {
        case audio
        case video
    }

    enum CompactSourceMark: Equatable, Sendable {
        case appleTV
        case appleMusic
        case spotify
        case youtube
        case netflix
        case disneyPlus
        case system(String)
    }

    struct MediaAccent: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        static let white = Self(red: 1, green: 1, blue: 1)
    }

    struct MediaSourceStyle: Equatable, Sendable {
        var id: MediaSource
        var displayName: String
        var applicationBundleIdentifier: String?
        var sourceMark: CompactSourceMark
        var fallbackSymbol: String
        var accent: MediaAccent
        var mediaKind: CompactMediaKind
        var canPlayPause: Bool
    }

    struct CompactMediaPresentation: Equatable {
        var source: MediaSourceStyle
        var primaryTitle: String
        var secondaryTitle: String
        var artwork: NSImage?
        var artworkIdentifier: String?
        var isPlaying: Bool
        var accentColor: MediaAccent
        var mediaKind: CompactMediaKind
        var canPlayPause: Bool
        var preferredWidth: CGFloat
        var duration: TimeInterval
        var elapsedAtTimestamp: TimeInterval
        var timestamp: Date
        var playbackRate: Double

        var isSeekable: Bool {
            duration.isFinite && duration > 0
        }

        func elapsed(at instant: Date = Date()) -> TimeInterval {
            let drift = isPlaying
                ? max(0, instant.timeIntervalSince(timestamp)) * playbackRate
                : 0
            let rawElapsed = elapsedAtTimestamp + drift
            guard isSeekable else { return max(0, rawElapsed) }
            return min(max(0, rawElapsed), duration)
        }

        func progress(at instant: Date = Date()) -> Double {
            guard isSeekable else { return 0 }
            return min(1, max(0, elapsed(at: instant) / duration))
        }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String?
        var artwork: NSImage?
        var duration: TimeInterval
        var elapsedAtTimestamp: TimeInterval
        var timestamp: Date
        var playbackRate: Double
        var sourceApplicationName: String? = nil
        var sourceBundleIdentifier: String? = nil
        var genre: String? = nil
        var mediaType: String? = nil
        var seriesTitle: String? = nil
        var episodeTitle: String? = nil
        var seasonNumber: Int? = nil
        var episodeNumber: Int? = nil
        var trackNumber: Int? = nil
        var totalTrackCount: Int? = nil
        var serviceIdentifier: String? = nil
        var contentIdentifier: String? = nil
        var artworkIdentifier: String? = nil

        var mediaSource: MediaSource {
            NowPlayingService.mediaSource(
                bundleIdentifier: sourceBundleIdentifier,
                applicationName: sourceApplicationName,
                serviceIdentifier: serviceIdentifier,
                contentIdentifier: contentIdentifier
            )
        }

        var isPlaying: Bool { playbackRate > 0.01 }

        var videoPresentation: VideoPresentation? {
            guard mediaSource.isVideo else { return nil }
            return NowPlayingService.videoPresentation(for: self)
        }

        var compactPresentation: CompactMediaPresentation {
            NowPlayingService.compactPresentation(for: self)
        }

        /// Live-extrapolated elapsed time at the moment of the call.
        func elapsed(at instant: Date = Date()) -> TimeInterval {
            let drift = isPlaying
                ? max(0, instant.timeIntervalSince(timestamp)) * playbackRate
                : 0
            let raw = elapsedAtTimestamp + drift
            if duration > 0 {
                return min(max(0, raw), duration)
            }
            return max(0, raw)
        }

        func progress(at instant: Date = Date()) -> Double {
            guard duration > 0 else { return 0 }
            return min(1, max(0, elapsed(at: instant) / duration))
        }
    }

    struct VideoPresentation: Equatable, Sendable {
        var title: String
        var subtitle: String?
        var seasonNumber: Int?
        var episodeNumber: Int?
        var genre: String?

        var isEpisode: Bool {
            seasonNumber != nil || episodeNumber != nil
        }

        var episodeLabel: String? {
            switch (seasonNumber, episodeNumber) {
            case let (.some(season), .some(episode)):
                "S\(season) · E\(episode)"
            case let (.some(season), .none):
                "Season \(season)"
            case let (.none, .some(episode)):
                "Episode \(episode)"
            case (.none, .none):
                nil
            }
        }
    }

    @Published private(set) var track: Track?

    private static let futureTimestampTolerance: TimeInterval = 2

    private let helper = MediaRemoteHelper()
    private var cancellable: AnyCancellable?
    private var lastArtworkBase64: String?
    private var pendingSeek: PendingSeek?
    private var tvMetadataTask: Task<Void, Never>?
    private var lastTVMetadataLookupKey: String?

    private static let seekReconciliationWindow: TimeInterval = 0.9

    private struct PendingSeek {
        var elapsed: TimeInterval
        var timestamp: Date
    }

    init() {
        cancellable = helper.$info
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                MainActor.assumeIsolated {
                    self?.applyInfo(info)
                }
            }
    }

    private func applyInfo(_ info: [String: Any]) {
        let now = Date()
        let title = (info["title"] as? String) ?? ""
        let artist = (info["artist"] as? String) ?? ""

        if title.isEmpty && artist.isEmpty {
            if track != nil { track = nil }
            return
        }

        let album = info["album"] as? String
        let sourceApplicationName = Self.normalizedMetadataString(info["sourceApplication"])
        let sourceBundleIdentifier = Self.normalizedMetadataString(info["sourceBundleIdentifier"])
        let genre = Self.normalizedMetadataString(info["genre"])
        let mediaType = Self.normalizedMetadataString(info["mediaType"])
        let seriesTitle = Self.normalizedMetadataString(info["seriesTitle"])
        let episodeTitle = Self.normalizedMetadataString(info["episodeTitle"])
        let seasonNumber = Self.integer(from: info["seasonNumber"])
        let episodeNumber = Self.integer(from: info["episodeNumber"])
        let trackNumber = Self.integer(from: info["trackNumber"])
        let totalTrackCount = Self.integer(from: info["totalTrackCount"])
        let serviceIdentifier = Self.normalizedMetadataString(info["serviceIdentifier"])
        let contentIdentifier = Self.normalizedMetadataString(info["contentIdentifier"])
            ?? Self.normalizedMetadataString(info["contentURL"])
            ?? Self.normalizedMetadataString(info["uniqueIdentifier"])
        let previousTrack = track
        let isSameItem = previousTrack.map {
            Self.isSameMediaItem(
                $0,
                title: title,
                artist: artist,
                album: album
            )
        } ?? false

        let incomingDuration = Self.timeInterval(from: info["duration"])
        let incomingElapsed = Self.timeInterval(from: info["elapsed"])
        let duration: TimeInterval
        if let incomingDuration, incomingDuration > 0 {
            duration = incomingDuration
        } else if isSameItem, let previousTrack, previousTrack.duration > 0 {
            duration = previousTrack.duration
        } else {
            duration = 0
        }

        // Helper sends timestamp as seconds since reference date.
        let incomingTimestamp = Self.timeInterval(from: info["timestamp"])
            .map { Date(timeIntervalSinceReferenceDate: $0) }
        let rawRate = Self.timeInterval(from: info["rate"]) ?? 1
        let isPlayingFlag = (info["isPlaying"] as? Bool) ?? (rawRate > 0)
        let playbackRate = isPlayingFlag ? max(rawRate, 1) : 0

        var timestamp = Self.timelineTimestamp(incomingTimestamp, now: now)
        var elapsed: TimeInterval
        if let incomingElapsed, incomingElapsed.isFinite, incomingElapsed >= 0 {
            elapsed = Self.clampedElapsed(incomingElapsed, duration: duration)
        } else if isSameItem, let previousTrack {
            elapsed = Self.clampedElapsed(previousTrack.elapsed(at: now), duration: duration)
        } else {
            elapsed = 0
        }

        reconcilePendingSeek(
            now: now,
            isSameItem: isSameItem,
            duration: duration,
            playbackRate: playbackRate,
            elapsed: &elapsed,
            timestamp: &timestamp
        )

        let artwork: NSImage?
        let artworkIdentifier: String?
        if let b64 = info["artwork"] as? String {
            if b64 == lastArtworkBase64 {
                artwork = track?.artwork  // unchanged — reuse the existing image
                artworkIdentifier = track?.artworkIdentifier
            } else if let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
                lastArtworkBase64 = b64
                artwork = img
                artworkIdentifier = String(b64.hashValue)
            } else {
                artwork = track?.artwork
                artworkIdentifier = track?.artworkIdentifier
            }
        } else if isSameItem {
            // Apple TV may omit artwork from intermediate timeline updates.
            // Keep the episode still until the media item actually changes.
            artwork = previousTrack?.artwork
            artworkIdentifier = previousTrack?.artworkIdentifier
        } else {
            lastArtworkBase64 = nil
            artwork = nil
            artworkIdentifier = nil
        }

        let normalizedTrack = Track(
            title: title,
            artist: artist,
            album: (album?.isEmpty == false) ? album : nil,
            artwork: artwork,
            duration: duration,
            elapsedAtTimestamp: elapsed,
            timestamp: timestamp,
            playbackRate: playbackRate,
            sourceApplicationName: sourceApplicationName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            genre: genre,
            mediaType: mediaType,
            seriesTitle: seriesTitle ?? (isSameItem ? previousTrack?.seriesTitle : nil),
            episodeTitle: episodeTitle ?? (isSameItem ? previousTrack?.episodeTitle : nil),
            seasonNumber: seasonNumber ?? (isSameItem ? previousTrack?.seasonNumber : nil),
            episodeNumber: episodeNumber ?? (isSameItem ? previousTrack?.episodeNumber : nil),
            trackNumber: trackNumber,
            totalTrackCount: totalTrackCount,
            serviceIdentifier: serviceIdentifier,
            contentIdentifier: contentIdentifier,
            artworkIdentifier: artworkIdentifier
        )
        track = normalizedTrack
        requestTVMetadataIfNeeded(for: normalizedTrack)
    }

    nonisolated static func mediaSource(
        bundleIdentifier: String?,
        applicationName: String?,
        serviceIdentifier: String? = nil,
        contentIdentifier: String? = nil
    ) -> MediaSource {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let name = applicationName?.lowercased() ?? ""
        let service = serviceIdentifier?.lowercased() ?? ""
        let content = contentIdentifier?.lowercased() ?? ""
        let combinedServiceHint = "\(service) \(content)"

        if combinedServiceHint.contains("youtube")
            || bundle.contains("youtube")
            || name == "youtube" {
            return .youtube
        }
        if combinedServiceHint.contains("netflix")
            || bundle.contains("netflix")
            || name == "netflix" {
            return .netflix
        }
        if combinedServiceHint.contains("disneyplus")
            || combinedServiceHint.contains("disney+")
            || bundle.contains("disney")
            || name.contains("disney+") {
            return .disneyPlus
        }

        if bundle == "com.apple.music" || name == "music" || name.contains("apple music") {
            return .appleMusic
        }
        if bundle.contains("spotify") || name.contains("spotify") {
            return .spotify
        }
        if bundle == "com.apple.tv" || name == "tv" || name.contains("apple tv") {
            return .appleTV
        }
        return .other
    }

    private static func isSameMediaItem(
        _ track: Track,
        title: String,
        artist: String,
        album: String?
    ) -> Bool {
        track.title == title
            && track.artist == artist
            && track.album == ((album?.isEmpty == false) ? album : nil)
    }

    private static func timeInterval(from value: Any?) -> TimeInterval? {
        switch value {
        case let value as TimeInterval:
            value.isFinite ? value : nil
        case let value as NSNumber:
            value.doubleValue.isFinite ? value.doubleValue : nil
        case let value as String:
            Double(value).flatMap { $0.isFinite ? $0 : nil }
        default:
            nil
        }
    }

    private static func integer(from value: Any?) -> Int? {
        guard let number = timeInterval(from: value), number >= 0 else { return nil }
        return Int(number.rounded())
    }

    nonisolated static func videoPresentation(for track: Track) -> VideoPresentation {
        let parsed = parsedEpisodeNumbers(from: [track.album, track.title, track.artist])
        let season = positive(track.seasonNumber) ?? parsed.season
        let episode = positive(track.episodeNumber) ?? positive(track.trackNumber) ?? parsed.episode
        let explicitSeries = normalizedMetadataString(track.seriesTitle)
        let normalizedArtist = normalizedMetadataString(track.artist)
        let normalizedEpisodeTitle = normalizedMetadataString(track.episodeTitle)
        let normalizedTitle = normalizedMetadataString(track.title) ?? "Now Playing"
        let isEpisode = explicitSeries != nil || season != nil || episode != nil

        if isEpisode {
            return VideoPresentation(
                title: explicitSeries ?? normalizedArtist ?? normalizedTitle,
                subtitle: normalizedEpisodeTitle ?? (normalizedTitle == explicitSeries ? nil : normalizedTitle),
                seasonNumber: season,
                episodeNumber: episode,
                genre: normalizedMetadataString(track.genre)
            )
        }

        return VideoPresentation(
            title: normalizedTitle,
            subtitle: normalizedArtist ?? normalizedMetadataString(track.album),
            seasonNumber: nil,
            episodeNumber: nil,
            genre: normalizedMetadataString(track.genre)
        )
    }

    static func compactPresentation(for track: Track) -> CompactMediaPresentation {
        let source = mediaSourceStyle(for: track)
        let primaryTitle: String
        let secondaryTitle: String

        switch source.id {
        case .appleTV, .netflix, .disneyPlus:
            let video = videoPresentation(for: track)
            primaryTitle = normalizedMetadataString(video.subtitle)
                ?? normalizedMetadataString(video.title)
                ?? normalizedMetadataString(track.title)
                ?? source.displayName
            secondaryTitle = normalizedMetadataString(video.episodeLabel)
                ?? normalizedMetadataString(video.title == primaryTitle ? nil : video.title)
                ?? normalizedMetadataString(track.artist)
                ?? source.displayName
        case .youtube:
            primaryTitle = normalizedMetadataString(track.title) ?? source.displayName
            secondaryTitle = normalizedMetadataString(track.artist)
                ?? normalizedMetadataString(track.album)
                ?? source.displayName
        case .appleMusic, .spotify:
            primaryTitle = normalizedMetadataString(track.title) ?? source.displayName
            secondaryTitle = normalizedMetadataString(track.artist)
                ?? source.displayName
        case .other:
            primaryTitle = normalizedMetadataString(track.title) ?? "Now Playing"
            secondaryTitle = normalizedMetadataString(track.artist)
                ?? normalizedMetadataString(track.sourceApplicationName)
                ?? "Media"
        }

        let preferredWidth: CGFloat = switch source.id {
        case .youtube: 550
        case .appleTV, .netflix, .disneyPlus: 540
        case .appleMusic, .spotify: 500
        case .other: 500
        }

        return CompactMediaPresentation(
            source: source,
            primaryTitle: primaryTitle,
            secondaryTitle: secondaryTitle,
            artwork: track.artwork,
            artworkIdentifier: track.artworkIdentifier,
            isPlaying: track.isPlaying,
            accentColor: source.accent,
            mediaKind: source.mediaKind,
            canPlayPause: source.canPlayPause,
            preferredWidth: preferredWidth,
            duration: track.duration,
            elapsedAtTimestamp: track.elapsedAtTimestamp,
            timestamp: track.timestamp,
            playbackRate: track.playbackRate
        )
    }

    static func mediaSourceStyle(for track: Track) -> MediaSourceStyle {
        switch track.mediaSource {
        case .appleTV:
            MediaSourceStyle(
                id: .appleTV,
                displayName: "Apple TV",
                applicationBundleIdentifier: track.sourceBundleIdentifier ?? "com.apple.TV",
                sourceMark: .appleTV,
                fallbackSymbol: "applelogo",
                accent: .white,
                mediaKind: .video,
                canPlayPause: true
            )
        case .spotify:
            MediaSourceStyle(
                id: .spotify,
                displayName: "Spotify",
                applicationBundleIdentifier: track.sourceBundleIdentifier ?? "com.spotify.client",
                sourceMark: .spotify,
                fallbackSymbol: "waveform",
                accent: .init(red: 0.12, green: 0.84, blue: 0.38),
                mediaKind: .audio,
                canPlayPause: true
            )
        case .netflix:
            MediaSourceStyle(
                id: .netflix,
                displayName: "Netflix",
                applicationBundleIdentifier: nil,
                sourceMark: .netflix,
                fallbackSymbol: "play.fill",
                accent: .init(red: 0.90, green: 0.04, blue: 0.08),
                mediaKind: .video,
                canPlayPause: true
            )
        case .disneyPlus:
            MediaSourceStyle(
                id: .disneyPlus,
                displayName: "Disney+",
                applicationBundleIdentifier: track.sourceBundleIdentifier,
                sourceMark: .disneyPlus,
                fallbackSymbol: "sparkles.tv.fill",
                accent: .init(red: 0.24, green: 0.58, blue: 1.0),
                mediaKind: .video,
                canPlayPause: true
            )
        case .appleMusic:
            MediaSourceStyle(
                id: .appleMusic,
                displayName: "Apple Music",
                applicationBundleIdentifier: track.sourceBundleIdentifier ?? "com.apple.Music",
                sourceMark: .appleMusic,
                fallbackSymbol: "music.note",
                accent: .init(red: 1.0, green: 0.20, blue: 0.37),
                mediaKind: .audio,
                canPlayPause: true
            )
        case .youtube:
            MediaSourceStyle(
                id: .youtube,
                displayName: "YouTube",
                applicationBundleIdentifier: nil,
                sourceMark: .youtube,
                fallbackSymbol: "play.fill",
                accent: .init(red: 1.0, green: 0.0, blue: 0.08),
                mediaKind: .video,
                canPlayPause: true
            )
        case .other:
            MediaSourceStyle(
                id: .other,
                displayName: normalizedMetadataString(track.sourceApplicationName) ?? "Media",
                applicationBundleIdentifier: track.sourceBundleIdentifier,
                sourceMark: .system("play.fill"),
                fallbackSymbol: "play.fill",
                accent: .white,
                mediaKind: .audio,
                canPlayPause: true
            )
        }
    }

    nonisolated private static func parsedEpisodeNumbers(
        from values: [String?]
    ) -> (season: Int?, episode: Int?) {
        let text = values.compactMap { $0 }.joined(separator: " · ")
        let compact = firstMatch(in: text, pattern: #"(?i)\bS\s*(\d{1,3})\s*[·,;:._ -]?\s*E\s*(\d{1,4})\b"#)
        if compact.count == 2 {
            return (Int(compact[0]), Int(compact[1]))
        }

        let seasonAfterLabel = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:season|série|serie|řada)\s*(\d{1,3})\b"#
        ).first.flatMap(Int.init)
        let seasonBeforeLabel = firstMatch(
            in: text,
            pattern: #"(?i)\b(\d{1,3})\.?\s*(?:season|série|serie|řada)\b"#
        ).first.flatMap(Int.init)
        let episodeAfterLabel = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:episode|epizoda|díl|dil)\s*(\d{1,4})\b"#
        ).first.flatMap(Int.init)
        let episodeBeforeLabel = firstMatch(
            in: text,
            pattern: #"(?i)\b(\d{1,4})\.?\s*(?:episode|epizoda|díl|dil)\b"#
        ).first.flatMap(Int.init)
        return (seasonAfterLabel ?? seasonBeforeLabel, episodeAfterLabel ?? episodeBeforeLabel)
    }

    nonisolated private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func requestTVMetadataIfNeeded(for candidate: Track) {
        guard candidate.mediaSource == .appleTV,
              candidate.videoPresentation?.episodeLabel == nil || candidate.artwork == nil else { return }

        let lookupKey = [
            candidate.title,
            candidate.artist,
            candidate.album ?? "",
            candidate.contentIdentifier ?? "",
        ]
            .joined(separator: "\u{1F}")
        guard lastTVMetadataLookupKey != lookupKey else { return }
        lastTVMetadataLookupKey = lookupKey
        tvMetadataTask?.cancel()

        tvMetadataTask = Task { @MainActor [weak self] in
            let needsMetadata = candidate.videoPresentation?.episodeLabel == nil
            let metadataTask: Task<TVAppMetadataProvider.Metadata?, Never>? = needsMetadata
                ? Task.detached(priority: .utility) { TVAppMetadataProvider.fetch() }
                : nil
            let artworkTask: Task<Data?, Never>? = candidate.artwork == nil
                ? Task(priority: .utility) {
                    await AppleTVArtworkProvider.shared.artworkData(
                        title: candidate.episodeTitle ?? candidate.title,
                        seriesTitle: candidate.seriesTitle
                            ?? Self.normalizedMetadataString(candidate.artist)
                    )
                }
                : nil

            let metadata = await metadataTask?.value
            let artworkData = await artworkTask?.value
            guard !Task.isCancelled,
                  let self,
                  var current = self.track,
                  [
                    current.title,
                    current.artist,
                    current.album ?? "",
                    current.contentIdentifier ?? "",
                  ]
                    .joined(separator: "\u{1F}") == lookupKey else { return }

            if let metadata {
                current.seriesTitle = metadata.show ?? current.seriesTitle
                current.episodeTitle = metadata.episodeTitle ?? current.episodeTitle
                current.seasonNumber = metadata.seasonNumber ?? current.seasonNumber
                current.episodeNumber = metadata.episodeNumber ?? current.episodeNumber
                current.genre = metadata.genre ?? current.genre
            }
            if current.artwork == nil,
               let artworkData,
               let artwork = NSImage(data: artworkData) {
                current.artwork = artwork
                current.artworkIdentifier = "apple-tv-\(artworkData.hashValue)"
            }
            self.track = current
        }
    }

    nonisolated private static func firstMatch(
        in text: String,
        pattern: String
    ) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ) else { return [] }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    nonisolated private static func normalizedMetadataString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func timelineTimestamp(_ timestamp: Date?, now: Date) -> Date {
        guard let timestamp else { return now }
        guard timestamp.timeIntervalSinceReferenceDate > 0 else { return now }
        guard timestamp.timeIntervalSince(now) <= futureTimestampTolerance else { return now }
        return timestamp
    }

    private static func clampedElapsed(
        _ elapsed: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        guard duration > 0 else { return max(0, elapsed) }
        return min(max(0, elapsed), duration)
    }

    // MARK: - Commands

    func togglePlayPause() {
        helper.send("toggle")
    }

    func nextTrack() {
        helper.send("next")
    }

    func previousTrack() {
        helper.send("previous")
    }

    func seek(to elapsedTime: TimeInterval) {
        guard var current = track, current.duration > 0 else { return }
        let elapsed = Self.clampedElapsed(elapsedTime, duration: current.duration)
        current.elapsedAtTimestamp = elapsed
        current.timestamp = Date()
        pendingSeek = PendingSeek(elapsed: elapsed, timestamp: current.timestamp)
        track = current
        helper.send("seek:\(elapsed)")
    }

    private func reconcilePendingSeek(
        now: Date,
        isSameItem: Bool,
        duration: TimeInterval,
        playbackRate: Double,
        elapsed: inout TimeInterval,
        timestamp: inout Date
    ) {
        guard let pendingSeek else { return }
        guard isSameItem,
              duration > 0,
              now.timeIntervalSince(pendingSeek.timestamp) < Self.seekReconciliationWindow else {
            self.pendingSeek = nil
            return
        }

        let drift = playbackRate > 0.01
            ? max(0, now.timeIntervalSince(pendingSeek.timestamp)) * playbackRate
            : 0
        let optimisticElapsed = Self.clampedElapsed(
            pendingSeek.elapsed + drift,
            duration: duration
        )

        if abs(elapsed - optimisticElapsed) > 0.45 {
            elapsed = optimisticElapsed
            timestamp = now
        } else {
            self.pendingSeek = nil
        }
    }
}

extension NowPlayingService.CompactMediaPresentation: NotchActivityPresenting {
    var activityType: NotchActivityType { .media }
    var presentationID: String {
        [source.id.rawValue, primaryTitle, secondaryTitle, artworkIdentifier ?? "no-artwork"]
            .joined(separator: "|")
    }
}

actor AppleTVArtworkProvider {
    static let shared = AppleTVArtworkProvider()

    private struct CacheEntry {
        var data: Data?
        var timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let failedLookupRetryInterval: TimeInterval = 300
    private let maximumHTMLBytes = 5_000_000
    private let maximumArtworkBytes = 12_000_000

    func artworkData(title: String, seriesTitle: String?) async -> Data? {
        let lookupKey = [title, seriesTitle ?? ""]
            .joined(separator: "\u{1F}")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if let entry = cache[lookupKey] {
            if let data = entry.data { return data }
            if Date().timeIntervalSince(entry.timestamp) < failedLookupRetryInterval { return nil }
        }

        let queries = [title, seriesTitle]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .reduce(into: [String]()) { result, query in
                guard !result.contains(query) else { return }
                result.append(query)
            }

        for query in queries {
            guard !Task.isCancelled else { return nil }
            if let pageURL = await resolvePageURL(query: query, expectedTitle: query),
               let imageURL = await resolveArtworkURL(pageURL: pageURL),
               let data = await downloadArtwork(from: imageURL) {
                cache[lookupKey] = CacheEntry(data: data, timestamp: Date())
                trimCacheIfNeeded()
                return data
            }
        }

        cache[lookupKey] = CacheEntry(data: nil, timestamp: Date())
        trimCacheIfNeeded()
        return nil
    }

    private func resolvePageURL(query: String, expectedTitle: String) async -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "tv.apple.com"
        let region = Locale.current.region?.identifier.lowercased() ?? "us"
        components.path = "/\(region)/search"
        components.queryItems = [URLQueryItem(name: "term", value: query)]
        guard let url = components.url,
              let html = await loadHTML(from: url) else { return nil }
        return AppleTVArtworkHTMLParser.pageURL(in: html, title: expectedTitle)
            ?? AppleTVArtworkHTMLParser.firstPlayablePageURL(in: html)
    }

    private func resolveArtworkURL(pageURL: URL) async -> URL? {
        guard let html = await loadHTML(from: pageURL) else { return nil }
        return AppleTVArtworkHTMLParser.openGraphArtworkURL(in: html)
    }

    private func loadHTML(from url: URL) async -> String? {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 8
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ","), forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= maximumHTMLBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func downloadArtwork(from url: URL) async -> Data? {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 8
        )
        request.setValue("image/avif,image/webp,image/jpeg,image/png", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= maximumArtworkBytes,
              !data.isEmpty else { return nil }
        return data
    }

    private func trimCacheIfNeeded() {
        guard cache.count > 16 else { return }
        let keysToRemove = cache
            .sorted { $0.value.timestamp < $1.value.timestamp }
            .prefix(cache.count - 16)
            .map(\.key)
        for key in keysToRemove { cache[key] = nil }
    }
}

enum AppleTVArtworkHTMLParser {
    nonisolated static func pageURL(in html: String, title: String) -> URL? {
        guard let titleData = try? JSONEncoder().encode(title),
              let titleLiteral = String(data: titleData, encoding: .utf8) else { return nil }
        let escapedTitle = NSRegularExpression.escapedPattern(for: titleLiteral)
        let pattern = "\\\"ariaLabel\\\":\(escapedTitle)[\\s\\S]{0,6000}?\\\"url\\\":\\\"(https:[^\\\"]+)\\\""
        return firstURL(in: html, pattern: pattern)
    }

    nonisolated static func firstPlayablePageURL(in html: String) -> URL? {
        firstURL(
            in: html,
            pattern: "\\\"url\\\":\\\"(https://tv\\.apple\\.com/[^\\\"]+/(?:episode|movie)/[^\\\"]+)\\\""
        )
    }

    nonisolated static func openGraphArtworkURL(in html: String) -> URL? {
        firstURL(
            in: html,
            pattern: #"<meta\s+property="og:image"\s+content="([^"]+)""#
        ) ?? firstURL(
            in: html,
            pattern: #"<meta\s+content="([^"]+)"\s+property="og:image""#
        )
    }

    nonisolated private static func firstURL(in text: String, pattern: String) -> URL? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let captured = String(text[range])
        let decoded = decodeJSONStringFragment(captured)
            .replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: decoded)
    }

    nonisolated private static func decodeJSONStringFragment(_ value: String) -> String {
        let wrapped = "\"\(value)\""
        guard let data = wrapped.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return value.replacingOccurrences(of: "\\/", with: "/")
        }
        return decoded
    }
}

private enum TVAppMetadataProvider {
    struct Metadata: Sendable {
        var show: String?
        var episodeTitle: String?
        var seasonNumber: Int?
        var episodeNumber: Int?
        var genre: String?
    }

    nonisolated static func fetch() -> Metadata? {
        let script = #"""
        tell application "TV"
            set currentItem to current track
            set showName to ""
            set episodeName to ""
            set seasonValue to ""
            set episodeValue to ""
            set genreValue to ""
            try
                set showName to show of currentItem as text
            end try
            try
                set episodeName to name of currentItem as text
            end try
            try
                set seasonValue to season number of currentItem as text
            end try
            try
                set episodeValue to episode number of currentItem as text
            end try
            try
                set genreValue to genre of currentItem as text
            end try
            set delimiterValue to ASCII character 30
            return showName & delimiterValue & episodeName & delimiterValue & seasonValue & delimiterValue & episodeValue & delimiterValue & genreValue
        end tell
        """#

        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = errorOutput
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        guard completion.wait(timeout: .now() + 4) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let fields = raw.split(separator: "\u{1E}", omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count == 5 else { return nil }

        func text(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func positiveInteger(_ value: String) -> Int? {
            guard let number = Int(value), number > 0 else { return nil }
            return number
        }

        return Metadata(
            show: text(fields[0]),
            episodeTitle: text(fields[1]),
            seasonNumber: positiveInteger(fields[2]),
            episodeNumber: positiveInteger(fields[3]),
            genre: text(fields[4])
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
