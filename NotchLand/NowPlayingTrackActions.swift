//
//  NowPlayingTrackActions.swift
//  NotchLand
//
//  Contextual actions for the current MediaRemote item. UI stays declarative;
//  app launching and pasteboard writes are isolated behind injectable adapters.
//

import AppKit
import Combine
import Foundation

struct NowPlayingTrackActionsPresentation: Equatable {
    let title: String
    let artist: String?
    let album: String?
    let sourceName: String
    let sourceBundleIdentifier: String?
    let duration: TimeInterval
    let elapsedAtTimestamp: TimeInterval
    let timestamp: Date
    let playbackRate: Double

    init(track: NowPlayingService.Track) {
        let normalizedArtist = Self.normalized(track.artist)
        title = Self.normalized(track.title) ?? "Now Playing"
        artist = normalizedArtist
        album = Self.normalized(track.album)
        sourceName = Self.normalized(track.sourceApplicationName)
            ?? track.compactPresentation.source.displayName
        sourceBundleIdentifier = Self.normalized(track.sourceBundleIdentifier)
            ?? track.compactPresentation.source.applicationBundleIdentifier
        duration = max(0, track.duration)
        elapsedAtTimestamp = max(0, track.elapsedAtTimestamp)
        timestamp = track.timestamp
        playbackRate = max(0, track.playbackRate)
    }

    var compactMetadata: String {
        guard let artist else { return title }
        return "\(title) — \(artist)"
    }

    var detailedMetadata: String {
        [compactMetadata, album]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    var isSeekable: Bool { duration > 0 }

    func elapsed(at date: Date = .now) -> TimeInterval {
        let drift = playbackRate > 0.01
            ? max(0, date.timeIntervalSince(timestamp)) * playbackRate
            : 0
        return min(duration, max(0, elapsedAtTimestamp + drift))
    }

    func seekTarget(by delta: TimeInterval, at date: Date = .now) -> TimeInterval? {
        guard isSeekable, delta.isFinite else { return nil }
        return min(duration, max(0, elapsed(at: date) + delta))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

@MainActor
protocol NowPlayingApplicationOpening {
    func applicationURL(for bundleIdentifier: String) -> URL?
    func openApplication(at url: URL) async throws
}

@MainActor
struct WorkspaceNowPlayingApplicationOpener: NowPlayingApplicationOpening {
    func applicationURL(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(at url: URL) async throws {
        _ = try await NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

@MainActor
protocol NowPlayingPasteboardWriting {
    @discardableResult
    func write(_ value: String) -> Bool
}

@MainActor
struct GeneralNowPlayingPasteboardWriter: NowPlayingPasteboardWriting {
    @discardableResult
    func write(_ value: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }
}

@MainActor
final class NowPlayingTrackActionsController: ObservableObject {
    enum Feedback: Equatable {
        case idle
        case success(String)
        case failure(String)

        var symbolName: String {
            switch self {
            case .idle: "ellipsis"
            case .success: "checkmark"
            case .failure: "exclamationmark"
            }
        }

        var accessibilityValue: String? {
            switch self {
            case .idle: nil
            case let .success(message), let .failure(message): message
            }
        }
    }

    @Published private(set) var feedback: Feedback = .idle
    @Published private(set) var isOpeningSource = false

    private let applicationOpener: NowPlayingApplicationOpening
    private let pasteboardWriter: NowPlayingPasteboardWriting
    private var feedbackResetTask: Task<Void, Never>?

    init(
        applicationOpener: NowPlayingApplicationOpening,
        pasteboardWriter: NowPlayingPasteboardWriting
    ) {
        self.applicationOpener = applicationOpener
        self.pasteboardWriter = pasteboardWriter
    }

    convenience init() {
        self.init(
            applicationOpener: WorkspaceNowPlayingApplicationOpener(),
            pasteboardWriter: GeneralNowPlayingPasteboardWriter()
        )
    }

    func canOpenSource(_ presentation: NowPlayingTrackActionsPresentation) -> Bool {
        guard let bundleIdentifier = presentation.sourceBundleIdentifier else { return false }
        return applicationOpener.applicationURL(for: bundleIdentifier) != nil
    }

    @discardableResult
    func openSource(_ presentation: NowPlayingTrackActionsPresentation) async -> Bool {
        guard !isOpeningSource,
              let bundleIdentifier = presentation.sourceBundleIdentifier,
              let applicationURL = applicationOpener.applicationURL(for: bundleIdentifier) else {
            present(.failure("Source application is unavailable"))
            return false
        }

        isOpeningSource = true
        defer { isOpeningSource = false }
        do {
            try await applicationOpener.openApplication(at: applicationURL)
            present(.success("Opened \(presentation.sourceName)"))
            return true
        } catch {
            present(.failure("Could not open \(presentation.sourceName)"))
            return false
        }
    }

    @discardableResult
    func copyCompactMetadata(_ presentation: NowPlayingTrackActionsPresentation) -> Bool {
        copy(presentation.compactMetadata, successMessage: "Track copied")
    }

    @discardableResult
    func copyDetailedMetadata(_ presentation: NowPlayingTrackActionsPresentation) -> Bool {
        copy(presentation.detailedMetadata, successMessage: "Details copied")
    }

    func confirmSeek(seconds: TimeInterval) {
        let amount = Int(abs(seconds).rounded())
        present(.success(seconds < 0 ? "Back \(amount) seconds" : "Forward \(amount) seconds"))
    }

    private func copy(_ value: String, successMessage: String) -> Bool {
        guard pasteboardWriter.write(value) else {
            present(.failure("Could not copy metadata"))
            return false
        }
        present(.success(successMessage))
        return true
    }

    private func present(_ feedback: Feedback) {
        feedbackResetTask?.cancel()
        self.feedback = feedback
        feedbackResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.feedback = .idle
            self?.feedbackResetTask = nil
        }
    }
}
