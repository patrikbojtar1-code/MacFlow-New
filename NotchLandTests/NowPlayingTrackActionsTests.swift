import AppKit
import Testing
@testable import NotchLand

@MainActor
struct NowPlayingTrackActionsTests {
    @Test func presentationBuildsCleanClipboardMetadata() {
        let presentation = NowPlayingTrackActionsPresentation(track: track())

        #expect(presentation.compactMetadata == "Midnight City — M83")
        #expect(presentation.detailedMetadata == "Midnight City — M83\nHurry Up, We're Dreaming")
        #expect(presentation.sourceBundleIdentifier == "com.apple.Music")
    }

    @Test func relativeSeekClampsAtBothTimelineEdges() {
        let beginning = NowPlayingTrackActionsPresentation(
            track: track(elapsed: 5, timestamp: .now, playbackRate: 0)
        )
        let ending = NowPlayingTrackActionsPresentation(
            track: track(elapsed: 238, timestamp: .now, playbackRate: 0)
        )

        #expect(beginning.seekTarget(by: -15) == 0)
        #expect(ending.seekTarget(by: 15) == 244)
    }

    @Test func controllerCopiesMetadataThroughInjectedPasteboard() {
        let pasteboard = FakeNowPlayingPasteboard()
        let controller = NowPlayingTrackActionsController(
            applicationOpener: FakeNowPlayingApplicationOpener(),
            pasteboardWriter: pasteboard
        )
        let presentation = NowPlayingTrackActionsPresentation(track: track())

        #expect(controller.copyDetailedMetadata(presentation))
        #expect(pasteboard.value == presentation.detailedMetadata)
        #expect(controller.feedback == .success("Details copied"))
    }

    @Test func controllerOpensResolvedSourceApplication() async {
        let opener = FakeNowPlayingApplicationOpener()
        let controller = NowPlayingTrackActionsController(
            applicationOpener: opener,
            pasteboardWriter: FakeNowPlayingPasteboard()
        )
        let presentation = NowPlayingTrackActionsPresentation(track: track())

        #expect(controller.canOpenSource(presentation))
        #expect(await controller.openSource(presentation))
        #expect(opener.openedURL == opener.applicationURL)
        #expect(controller.feedback == .success("Opened Music"))
    }

    private func track(
        elapsed: TimeInterval = 86,
        timestamp: Date = .now,
        playbackRate: Double = 1
    ) -> NowPlayingService.Track {
        NowPlayingService.Track(
            title: " Midnight City ",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            artwork: nil,
            duration: 244,
            elapsedAtTimestamp: elapsed,
            timestamp: timestamp,
            playbackRate: playbackRate,
            sourceApplicationName: "Music",
            sourceBundleIdentifier: "com.apple.Music"
        )
    }
}

@MainActor
private final class FakeNowPlayingApplicationOpener: NowPlayingApplicationOpening {
    let applicationURL = URL(fileURLWithPath: "/Applications/Music.app")
    var openedURL: URL?

    func applicationURL(for bundleIdentifier: String) -> URL? {
        bundleIdentifier == "com.apple.Music" ? applicationURL : nil
    }

    func openApplication(at url: URL) async throws {
        openedURL = url
    }
}

@MainActor
private final class FakeNowPlayingPasteboard: NowPlayingPasteboardWriting {
    var value: String?

    func write(_ value: String) -> Bool {
        self.value = value
        return true
    }
}
