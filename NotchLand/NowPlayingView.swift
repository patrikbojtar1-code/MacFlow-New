//
//  NowPlayingView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Music UI that the FloatingNotch renders when NowPlayingService has a
//  track. Two states:
//    * Collapsed: artwork on the left of the notch, animated EQ bars on the right.
//    * Expanded:  full media controls — large artwork, title/artist, scrubber,
//                 prev/play/next, output device button. Replicates Alcove.
//

import AppKit
import Combine
import CoreImage
import SwiftUI

// MARK: - Constants for the notch sizing math (referenced by WindowManager).

enum NowPlayingMetrics {
    /// Width of the collapsed pill when music is playing. Wider than the bare
    /// notch so the artwork (left) and EQ bars (right) flank the hardware notch.
    static let collapsedWidth: CGFloat = 250
    static let compactHeight: CGFloat = NotchLayoutMetrics.bodySize(for: .small).height
    static let compactBottomCornerRadius: CGFloat = 22
    static let compactHoverWidthExpansion: CGFloat = 10
    /// Matches the measured 13-inch M4 MacBook Air safe-area cutout.
    static let compactHardwareBridgeHeight: CGFloat = 32
    static let compactHardwareBridgeBottomRadius: CGFloat = 8
    /// Height matches the bare collapsed notch — we don't grow vertically.
    static let collapsedExtraHeight: CGFloat = 0
    /// Extra height added under the collapsed pill when the cursor is hovering,
    /// to host the scrolling song-title marquee.
    static let hoverExtraHeight: CGFloat = 24
    /// Standalone expanded media footprint. The widget host provides the same
    /// width and a 244pt content stage below its module rail.
    static let expandedSize = CGSize(width: 580, height: 244)
    /// Edge inset around the artwork / bars in the collapsed pill.
    static let collapsedSidePadding: CGFloat = 10
    /// Side artwork in the collapsed pill.
    static let collapsedArtSize: CGFloat = 22

    static func compactHeight(for size: NotchSize) -> CGFloat {
        NotchLayoutMetrics.bodySize(for: size).height
    }

    static func compactBodyWidth(for size: NotchSize) -> CGFloat {
        NotchLayoutMetrics.bodySize(for: size).width
    }
}

/// A density-specific contract for the compact player. Keeping this separate
/// from the SwiftUI hierarchy prevents Small from becoming a scaled-down Large
/// layout and gives every density a deliberate information hierarchy.
nonisolated struct CompactMediaLayoutProfile: Equatable, Sendable {
    let sourceSize: CGFloat
    let titleSize: CGFloat
    let subtitleSize: CGFloat
    let horizontalPadding: CGFloat
    let identitySpacing: CGFloat
    let controlSpacing: CGFloat
    let controlDiameter: CGFloat
    let waveformWidth: CGFloat
    let showsPrevious: Bool
    let showsNext: Bool

    static func resolve(for size: NotchSize) -> Self {
        switch size {
        case .small:
            Self(
                sourceSize: 28,
                titleSize: 13,
                subtitleSize: 9.5,
                horizontalPadding: 12,
                identitySpacing: 8,
                controlSpacing: 7,
                controlDiameter: 28,
                waveformWidth: 30,
                showsPrevious: false,
                showsNext: false
            )
        case .medium:
            Self(
                sourceSize: 34,
                titleSize: 15,
                subtitleSize: 11,
                horizontalPadding: 15,
                identitySpacing: 10,
                controlSpacing: 7,
                controlDiameter: 30,
                waveformWidth: 38,
                showsPrevious: false,
                showsNext: true
            )
        case .large:
            Self(
                sourceSize: 40,
                titleSize: 16,
                subtitleSize: 12,
                horizontalPadding: 18,
                identitySpacing: 11,
                controlSpacing: 8,
                controlDiameter: 32,
                waveformWidth: 44,
                showsPrevious: true,
                showsNext: true
            )
        }
    }
}

nonisolated enum CompactMediaSwipeDirection: Equatable, Sendable {
    case previous
    case next

    var symbol: String {
        switch self {
        case .previous: "backward.fill"
        case .next: "forward.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .previous: "Previous track"
        case .next: "Next track"
        }
    }

    /// The visual grows from the same physical edge the pointer travels to.
    var emergesFromLeadingEdge: Bool {
        self == .previous
    }
}

/// Converts pointer movement into a deliberate media command. Horizontal
/// dominance prevents a diagonal or tiny click from accidentally changing the
/// song, while the rubber-band curve keeps the visual surface under control.
nonisolated enum CompactMediaGesturePolicy {
    static let activationThreshold: CGFloat = 54
    static let verticalTolerance: CGFloat = 34

    static func direction(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat
    ) -> CompactMediaSwipeDirection? {
        guard abs(horizontalTranslation) >= activationThreshold,
              abs(verticalTranslation) <= verticalTolerance,
              abs(horizontalTranslation) > abs(verticalTranslation) * 1.35 else { return nil }
        // Product gesture: left → right advances; right → left goes back.
        return horizontalTranslation > 0 ? .next : .previous
    }

    static func progress(for horizontalTranslation: CGFloat) -> CGFloat {
        min(1, abs(horizontalTranslation) / activationThreshold)
    }
}

private enum MediaSourceLogo {
    case application(NSImage)
    case youtube
    case netflix
    case disneyPlus
    case system(String)
}

private struct MediaSourceTheme {
    let name: String
    let symbol: String
    let logo: MediaSourceLogo
    let accent: Color
    let ambientAccent: Color
    let controlForeground: Color
    let usesWideArtwork: Bool

    static func resolve(for track: NowPlayingService.Track) -> Self {
        switch track.mediaSource {
        case .appleMusic:
            let accent = Color(red: 1.0, green: 0.20, blue: 0.37)
            return Self(
                name: "Apple Music",
                symbol: "music.note",
                logo: applicationLogo(
                    bundleIdentifier: track.sourceBundleIdentifier ?? "com.apple.Music",
                    fallback: "music.note"
                ),
                accent: accent,
                ambientAccent: track.artwork?.waveAccentColor() ?? accent,
                controlForeground: .white,
                usesWideArtwork: false
            )
        case .spotify:
            let accent = Color(red: 0.12, green: 0.84, blue: 0.38)
            return Self(
                name: "Spotify",
                symbol: "waveform.circle.fill",
                logo: applicationLogo(
                    bundleIdentifier: track.sourceBundleIdentifier ?? "com.spotify.client",
                    fallback: "waveform.circle.fill"
                ),
                accent: accent,
                ambientAccent: track.artwork?.waveAccentColor() ?? accent,
                controlForeground: .black,
                usesWideArtwork: false
            )
        case .appleTV:
            return Self(
                name: "Apple TV",
                symbol: "play.tv.fill",
                logo: applicationLogo(
                    bundleIdentifier: track.sourceBundleIdentifier ?? "com.apple.TV",
                    fallback: "play.tv.fill"
                ),
                accent: .white,
                ambientAccent: track.artwork?.waveAccentColor() ?? Color(white: 0.72),
                controlForeground: .black,
                usesWideArtwork: true
            )
        case .youtube:
            let accent = Color(red: 1.0, green: 0.0, blue: 0.08)
            return Self(
                name: "YouTube",
                symbol: "play.fill",
                logo: .youtube,
                accent: accent,
                ambientAccent: track.artwork?.waveAccentColor() ?? accent,
                controlForeground: .white,
                usesWideArtwork: true
            )
        case .netflix:
            let accent = Color(red: 0.90, green: 0.04, blue: 0.08)
            return Self(
                name: "Netflix",
                symbol: "play.rectangle.fill",
                logo: .netflix,
                accent: accent,
                ambientAccent: track.artwork?.waveAccentColor() ?? accent,
                controlForeground: .white,
                usesWideArtwork: true
            )
        case .disneyPlus:
            let accent = Color(red: 0.24, green: 0.58, blue: 1.0)
            return Self(
                name: "Disney+",
                symbol: "sparkles.tv.fill",
                logo: .disneyPlus,
                accent: accent,
                ambientAccent: track.artwork?.waveAccentColor() ?? accent,
                controlForeground: .white,
                usesWideArtwork: true
            )
        case .other:
            let accent = track.artwork?.waveAccentColor() ?? .white
            return Self(
                name: track.sourceApplicationName ?? "Now Playing",
                symbol: "play.circle.fill",
                logo: applicationLogo(
                    bundleIdentifier: track.sourceBundleIdentifier,
                    fallback: "play.circle.fill"
                ),
                accent: accent,
                ambientAccent: accent,
                controlForeground: .black,
                usesWideArtwork: false
            )
        }
    }

    private static func applicationLogo(
        bundleIdentifier: String?,
        fallback: String
    ) -> MediaSourceLogo {
        guard let bundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else {
            return .system(fallback)
        }
        return .application(NSWorkspace.shared.icon(forFile: applicationURL.path))
    }
}

private struct MediaSourceLogoView: View {
    let logo: MediaSourceLogo
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch logo {
            case let .application(image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            case .youtube:
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.0, blue: 0.08))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: size * 0.4, weight: .black))
                            .foregroundStyle(.white)
                            .offset(x: 0.5)
                    }
            case .netflix:
                Text("N")
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.90, green: 0.04, blue: 0.08))
            case .disneyPlus:
                Text("Disney+")
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            case let .system(symbol):
                Image(systemName: symbol)
                    .font(.system(size: size * 0.78, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

private enum ExpandedMediaTokens {
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 9
    static let identitySpacing: CGFloat = 18
    static let artworkSize = CGSize(width: 112, height: 112)
    static let wideArtworkSize = CGSize(width: 164, height: 154)
    static let artworkRadius: CGFloat = 18
    static let wideArtworkRadius: CGFloat = 15
    static let backgroundBlur: CGFloat = 42
    static let backgroundScale: CGFloat = 1.24
    static let controlSize: CGFloat = 36
    static let primaryControlSize: CGFloat = 42
}

// MARK: - Compact media presentation

struct NowPlayingCollapsedView: View {
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var settings: NotchSettings
    @Environment(\.effectiveNotchSize) private var effectiveNotchSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    let track: NowPlayingService.Track
    var isHovering: Bool = false
    var morphNamespace: Namespace.ID? = nil
    var gestureDirection: CompactMediaSwipeDirection? = nil
    var gestureProgress: CGFloat = 0
    @StateObject private var backgroundModel = CompactArtworkBackgroundModel()
    @State private var revealsContent = false

    private var presentation: NowPlayingService.CompactMediaPresentation {
        track.compactPresentation
    }

    var body: some View {
        CompactMediaContent(
            presentation: presentation,
            processedBackground: backgroundModel.image,
            backgroundIdentity: backgroundModel.identity,
            hardwareNotchWidth: CGFloat(settings.collapsedWidth),
            notchSize: effectiveNotchSize,
            isHovering: isHovering,
            revealsContent: revealsContent,
            accessibilityContrast: accessibilityContrast,
            reduceMotion: reduceMotion,
            morphNamespace: morphNamespace,
            gestureDirection: gestureDirection,
            gestureProgress: gestureProgress,
            onPrevious: previousTrack,
            onPlayPause: togglePlayback,
            onNext: nextTrack,
            onSeek: seek
        )
        .task(id: presentation.artworkIdentifier) {
            await backgroundModel.update(
                artwork: presentation.artwork,
                identifier: presentation.artworkIdentifier,
                reduceMotion: reduceMotion
            )
        }
        .onAppear {
            if reduceMotion {
                revealsContent = true
            } else {
                revealsContent = false
                Task { @MainActor in
                    await Task.yield()
                    revealsContent = true
                }
            }
        }
        .onChange(of: presentation.isPlaying) { _, isPlaying in
            announcePlaybackState(isPlaying: isPlaying)
        }
        .accessibilityAction(named: presentation.isPlaying ? "Pause" : "Play") {
            togglePlayback()
        }
        .accessibilityAction(named: "Previous track") {
            previousTrack()
        }
        .accessibilityAction(named: "Next track") {
            nextTrack()
        }
    }

    private func togglePlayback() {
        guard presentation.canPlayPause else { return }
        NotchHaptics.perform(.navigation)
        nowPlaying.togglePlayPause()
    }

    private func previousTrack() {
        NotchHaptics.perform(.navigation)
        nowPlaying.previousTrack()
    }

    private func nextTrack() {
        NotchHaptics.perform(.navigation)
        nowPlaying.nextTrack()
    }

    private func seek(to elapsed: TimeInterval) {
        guard presentation.isSeekable else { return }
        NotchHaptics.perform(.navigation)
        nowPlaying.seek(to: elapsed)
    }

    private func announcePlaybackState(isPlaying: Bool) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: isPlaying ? "Playback resumed" : "Playback paused",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}

struct CompactMediaContent: View {
    let presentation: NowPlayingService.CompactMediaPresentation
    let processedBackground: NSImage?
    let backgroundIdentity: String?
    let hardwareNotchWidth: CGFloat
    var notchSize: NotchSize = .small
    let isHovering: Bool
    let revealsContent: Bool
    let accessibilityContrast: ColorSchemeContrast
    let reduceMotion: Bool
    var morphNamespace: Namespace.ID? = nil
    var gestureDirection: CompactMediaSwipeDirection? = nil
    var gestureProgress: CGFloat = 0
    var onPrevious: () -> Void = {}
    let onPlayPause: () -> Void
    var onNext: () -> Void = {}
    var onSeek: (TimeInterval) -> Void = { _ in }

    private var profile: CompactMediaLayoutProfile {
        .resolve(for: notchSize)
    }

    private var accent: Color {
        Color(presentation.accentColor)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CompactMediaBackground(
                image: processedBackground,
                identity: backgroundIdentity,
                accent: accent,
                isPlaying: presentation.isPlaying,
                isHovering: isHovering,
                accessibilityContrast: accessibilityContrast,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let gestureDirection, gestureProgress > 0 {
                CompactMediaGestureBackground(
                    direction: gestureDirection,
                    progress: gestureProgress,
                    accent: accent
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            CompactHardwareBridgeShape(
                bottomRadius: NowPlayingMetrics.compactHardwareBridgeBottomRadius
            )
            .fill(.black)
            .frame(
                width: hardwareNotchWidth,
                height: NowPlayingMetrics.compactHardwareBridgeHeight
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .shadow(color: .black.opacity(0.34), radius: 4, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            HStack(spacing: 0) {
                identityWing
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: hardwareNotchWidth)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                transportWing
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, profile.horizontalPadding)
            .frame(height: max(profile.sourceSize, notchSize == .small ? 33 : 38))
            .frame(maxHeight: .infinity, alignment: .center)
            .scaleEffect(1 - min(0.012, gestureProgress * 0.012))
            .scaleEffect(isHovering ? 1.006 : 1, anchor: .center)
            .animation(NotchMotionGraph.animation(for: .hover, reduceMotion: reduceMotion), value: isHovering)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var identityWing: some View {
        HStack(spacing: profile.identitySpacing) {
            CompactSourceGestureMorph(
                style: presentation.source,
                size: profile.sourceSize,
                direction: gestureDirection,
                progress: gestureProgress,
                accent: accent
            )
            .scaleEffect(revealsContent && !reduceMotion ? 1 : 0.88)
            .opacity(revealsContent ? 1 : 0)
            .animation(entranceAnimation(delay: 0), value: revealsContent)

            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.primaryTitle)
                    .font(.system(size: profile.titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(notchSize == .small ? 0.76 : 0.86)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .contentTransition(.interpolate)

                Text(presentation.secondaryTitle)
                    .font(.system(size: profile.subtitleSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(accessibilityContrast == .increased ? 0.86 : 0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                    .truncationMode(.tail)
                    .contentTransition(.interpolate)

                CompactMediaTimeline(
                    presentation: presentation,
                    accent: accent,
                    onSeek: onSeek
                )
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: gestureDirection == .previous ? gestureProgress * 3 : 0)
            .opacity(gestureDirection == .previous ? 1 - gestureProgress * 0.22 : 1)
            .offset(x: revealsContent || reduceMotion ? 0 : -4)
            .opacity(revealsContent ? 1 : 0)
            .animation(entranceAnimation(delay: 0.035), value: revealsContent)
            .animation(
                NotchMotionGraph.animation(for: .selection, reduceMotion: reduceMotion),
                value: presentation.primaryTitle
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.source.displayName), \(presentation.primaryTitle)")
        .accessibilityValue(presentation.secondaryTitle)
    }

    private var transportWing: some View {
        let nextMorphProgress = gestureDirection == .next
            ? min(1, max(0, gestureProgress))
            : 0
        let nextControlOffset = profile.showsNext
            ? profile.controlDiameter - 2 + profile.controlSpacing
            : 0

        return HStack(spacing: profile.controlSpacing) {
            if profile.showsPrevious {
                CompactTransportButton(
                    symbol: "backward.fill",
                    label: "Previous",
                    diameter: profile.controlDiameter - 4,
                    isHoveringNotch: isHovering,
                    action: onPrevious
                )
                .opacity(1 - nextMorphProgress * 0.72)
            }

            CompactMediaWaveform(
                isPlaying: presentation.isPlaying,
                color: accent,
                isEmphasized: isHovering
            )
            .frame(width: profile.waveformWidth, height: notchSize == .large ? 19 : 17)
            .matchedGeometry(id: "music-eq", in: morphNamespace)
            .opacity(1 - nextMorphProgress * 0.78)
            .scaleEffect(1 - nextMorphProgress * 0.08)
            .accessibilityHidden(true)

            CompactTransportButton(
                symbol: presentation.isPlaying ? "pause.fill" : "play.fill",
                morphSymbol: "forward.fill",
                morphProgress: nextMorphProgress,
                label: presentation.isPlaying ? "Pause" : "Play",
                diameter: profile.controlDiameter,
                isProminent: true,
                isEnabled: presentation.canPlayPause,
                isHoveringNotch: isHovering,
                accent: accent,
                action: onPlayPause
            )
            .offset(x: nextControlOffset * nextMorphProgress)
            .zIndex(2)

            if profile.showsNext {
                CompactTransportButton(
                    symbol: "forward.fill",
                    label: "Next",
                    diameter: profile.controlDiameter - 4,
                    isHoveringNotch: isHovering,
                    action: onNext
                )
                .opacity(1 - min(1, nextMorphProgress * 2.8))
                .scaleEffect(1 - nextMorphProgress * 0.16)
            }
        }
        .opacity(revealsContent ? (isHovering ? 1 : 0.9) : 0)
        .animation(entranceAnimation(delay: 0.07), value: revealsContent)
        .animation(
            NotchMotionGraph.animation(for: .selection, reduceMotion: reduceMotion),
            value: presentation.isPlaying
        )
    }

    private func entranceAnimation(delay: TimeInterval) -> Animation {
        if reduceMotion { return NotchMotionGraph.reduced.animation }
        return NotchMotionGraph.animation(for: .contentEnter).delay(delay)
    }
}

private struct CompactHardwareBridgeShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: rect.origin)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct CompactMediaBackground: View {
    let image: NSImage?
    let identity: String?
    let accent: Color
    let isPlaying: Bool
    let isHovering: Bool
    let accessibilityContrast: ColorSchemeContrast
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Color.black

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .id(identity)
                    .opacity(isPlaying ? (isHovering ? 0.78 : 0.72) : 0.58)
                    .transition(.opacity)
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.18), .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(accessibilityContrast == .increased ? 0.68 : 0.42),
                    Color.black.opacity(accessibilityContrast == .increased ? 0.78 : 0.58),
                    Color.black.opacity(accessibilityContrast == .increased ? 0.86 : 0.72),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [.black.opacity(0.12), .clear, .black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )

            accent
                .opacity(isPlaying ? 0.075 : 0.035)
                .blur(radius: 20)
                .blendMode(.screen)
        }
        .animation(
            reduceMotion ? NotchMotionGraph.reduced.animation : .easeInOut(duration: 0.32),
            value: identity
        )
        .animation(NotchMotionGraph.animation(for: .selection, reduceMotion: reduceMotion), value: isPlaying)
        .allowsHitTesting(false)
    }
}

private struct CompactSourceIdentityView: View {
    let style: NowPlayingService.MediaSourceStyle
    let size: CGFloat

    private var installedIcon: NSImage? {
        CompactApplicationIconCache.icon(for: style.applicationBundleIdentifier)
    }

    var body: some View {
        Group {
            if let installedIcon {
                Image(nsImage: installedIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                fallbackMark
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.75)
        }
        .accessibilityLabel(style.displayName)
    }

    @ViewBuilder
    private var fallbackMark: some View {
        switch style.sourceMark {
        case .appleTV:
            HStack(spacing: 1) {
                Image(systemName: "applelogo")
                Text("tv")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.075))
        case .appleMusic:
            Image(systemName: "music.note")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 1.0, green: 0.20, blue: 0.37).opacity(0.72))
        case .spotify:
            Image(systemName: "wave.3.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.12, green: 0.84, blue: 0.38))
        case .youtube:
            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)
                .offset(x: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 1.0, green: 0.0, blue: 0.08))
        case .netflix:
            Text("N")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.90, green: 0.04, blue: 0.08))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
        case .disneyPlus:
            Text("Disney+")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.12, green: 0.32, blue: 0.76))
        case let .system(symbol):
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.075))
        }
    }
}

/// The leading source tile is the physical origin of Previous. The frame never
/// changes, so the source artwork and backward glyph share the exact same
/// center and corner geometry throughout the interactive transition.
private struct CompactSourceGestureMorph: View {
    let style: NowPlayingService.MediaSourceStyle
    let size: CGFloat
    let direction: CompactMediaSwipeDirection?
    let progress: CGFloat
    let accent: Color

    private var morphProgress: CGFloat {
        guard direction == .previous else { return 0 }
        return min(1, max(0, progress))
    }

    private var easedProgress: CGFloat {
        let value = morphProgress
        return value * value * (3 - 2 * value)
    }

    var body: some View {
        ZStack {
            CompactSourceIdentityView(style: style, size: size)
                .opacity(1 - easedProgress)
                .scaleEffect(1 - easedProgress * 0.14)
                .blur(radius: easedProgress * 1.2)

            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .fill(accent.opacity(0.12 + easedProgress * 0.34))
                }
                .overlay {
                    Circle()
                        .stroke(
                            .white.opacity(0.12 + easedProgress * 0.34),
                            lineWidth: 0.75 + easedProgress * 0.45
                        )
                }
                .opacity(easedProgress)

            Image(systemName: "backward.fill")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(0.68 + easedProgress * 0.32)
                .offset(x: -3 * (1 - easedProgress))
                .opacity(easedProgress)
        }
        .frame(width: size, height: size)
        .scaleEffect(1 + easedProgress * 0.16)
        .shadow(color: accent.opacity(easedProgress * 0.42), radius: 12)
        .accessibilityLabel(
            morphProgress > 0.5 ? "Previous track" : style.displayName
        )
    }
}

@MainActor
private enum CompactApplicationIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        let key = bundleIdentifier as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

private struct CompactMediaTimeline: View {
    let presentation: NowPlayingService.CompactMediaPresentation
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedProgress: Double?
    @State private var isHovering = false

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: AppMotion.FrameInterval.lowFrequency,
                paused: !presentation.isPlaying || !presentation.isSeekable
            )
        ) { context in
            GeometryReader { proxy in
                let progress = draggedProgress ?? presentation.progress(at: context.date)
                let clampedProgress = CGFloat(min(1, max(0, progress)))
                let fillWidth = proxy.size.width * clampedProgress

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(presentation.isSeekable ? 0.16 : 0.07))

                    Capsule(style: .continuous)
                        .fill(accent.opacity(presentation.isPlaying ? 0.95 : 0.62))
                        .frame(width: fillWidth)

                    if isHovering, presentation.isSeekable {
                        Circle()
                            .fill(.white)
                            .frame(width: 5, height: 5)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: min(max(0, fillWidth - 2.5), max(0, proxy.size.width - 5)))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: isHovering ? 2.5 : 2)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(seekGesture(width: proxy.size.width))
            }
        }
        .onHover { isHovering = $0 }
        .animation(
            NotchMotionGraph.animation(for: .hover, reduceMotion: reduceMotion),
            value: isHovering
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(accessibilityProgress)
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard presentation.isSeekable, width > 0 else { return }
                draggedProgress = min(1, max(0, Double(value.location.x / width)))
            }
            .onEnded { value in
                guard presentation.isSeekable, width > 0 else {
                    draggedProgress = nil
                    return
                }
                let progress = min(1, max(0, Double(value.location.x / width)))
                onSeek(progress * presentation.duration)
                draggedProgress = nil
            }
    }

    private var accessibilityProgress: String {
        guard presentation.isSeekable else { return "Unavailable" }
        return "\(Int((presentation.progress() * 100).rounded())) percent"
    }
}

private struct CompactTransportButton: View {
    let symbol: String
    var morphSymbol: String? = nil
    var morphProgress: CGFloat = 0
    let label: String
    let diameter: CGFloat
    var isProminent = false
    var isEnabled = true
    let isHoveringNotch: Bool
    var accent: Color = .white
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var clampedMorphProgress: CGFloat {
        min(1, max(0, morphProgress))
    }

    private var easedMorphProgress: CGFloat {
        let value = clampedMorphProgress
        return value * value * (3 - 2 * value)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: isProminent ? 15.5 : 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.96 : 0.38))
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(1 - easedMorphProgress * 0.18)
                    .offset(x: -2 * easedMorphProgress)
                    .opacity(1 - easedMorphProgress)

                if let morphSymbol {
                    Image(systemName: morphSymbol)
                        .font(.system(size: 12 + easedMorphProgress * 2.5, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(0.68 + easedMorphProgress * 0.32)
                        .offset(x: 3 * (1 - easedMorphProgress))
                        .opacity(easedMorphProgress)
                }
            }
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
            .overlay {
                Circle()
                    .stroke(
                        .white.opacity(easedMorphProgress * 0.38),
                        lineWidth: 0.75 + easedMorphProgress * 0.5
                    )
            }
            .contentShape(Circle())
            .scaleEffect(
                (isHovering ? 1.07 : (isHoveringNotch && isProminent ? 1.025 : 1))
                    + easedMorphProgress * 0.14
            )
            .shadow(
                color: accent.opacity(easedMorphProgress * 0.44),
                radius: 12 * easedMorphProgress
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .animation(
            NotchMotionGraph.animation(for: .hover, reduceMotion: reduceMotion),
            value: isHovering
        )
        .accessibilityLabel(label)
        .help(label)
    }

    private var background: Color {
        if easedMorphProgress > 0 {
            return accent.opacity(0.12 + easedMorphProgress * 0.38)
        }
        guard isProminent || isHovering else { return .clear }
        if isHovering { return .white.opacity(0.17) }
        return .white.opacity(isHoveringNotch ? 0.11 : 0.075)
    }
}

/// Ambient color and the edge bubble are rendered inside CompactMediaContent,
/// so the notch's existing clip shape naturally trims the effect at its curved
/// boundary. It therefore feels like the black surface itself is reacting.
private struct CompactMediaGestureBackground: View {
    let direction: CompactMediaSwipeDirection
    let progress: CGFloat
    let accent: Color

    private var clampedProgress: CGFloat {
        min(1, max(0, progress))
    }

    private var easedProgress: CGFloat {
        let value = clampedProgress
        return value * value * (3 - 2 * value)
    }

    var body: some View {
        GeometryReader { proxy in
            let bubbleWidth = 44 + easedProgress * 92
            let bubbleHeight = max(38, proxy.size.height * (0.74 + easedProgress * 0.34))

            ZStack {
                edgeSweep

                HStack(spacing: 0) {
                    if direction.emergesFromLeadingEdge {
                        bubble(width: bubbleWidth, height: bubbleHeight)
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                        bubble(width: bubbleWidth, height: bubbleHeight)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private var edgeSweep: some View {
        LinearGradient(
            colors: direction.emergesFromLeadingEdge
                ? [accent.opacity(0.29 * easedProgress), accent.opacity(0.08 * easedProgress), .clear]
                : [.clear, accent.opacity(0.08 * easedProgress), accent.opacity(0.29 * easedProgress)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .blendMode(.screen)
        .opacity(0.35 + easedProgress * 0.65)
    }

    private func bubble(width: CGFloat, height: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accent.opacity(0.38 * easedProgress),
                        accent.opacity(0.13 * easedProgress),
                        .clear,
                    ],
                    startPoint: direction.emergesFromLeadingEdge ? .leading : .trailing,
                    endPoint: direction.emergesFromLeadingEdge ? .trailing : .leading
                )
            )
            .frame(width: width, height: height)
            .blur(radius: 1.5 + (1 - easedProgress) * 3)
            .offset(x: direction.emergesFromLeadingEdge
                ? -30 * (1 - easedProgress)
                : 30 * (1 - easedProgress))
            .shadow(color: accent.opacity(0.28 * easedProgress), radius: 18)
    }
}

private struct CompactMediaWaveform: View {
    let isPlaying: Bool
    let color: Color
    let isEmphasized: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: AppMotion.FrameInterval.ambient, paused: !isPlaying || reduceMotion)) { timeline in
            Canvas { context, size in
                let barCount = 7
                let barWidth: CGFloat = 2.4
                let spacing: CGFloat = 3
                let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
                let originX = (size.width - totalWidth) / 2
                let time = timeline.date.timeIntervalSinceReferenceDate

                for index in 0..<barCount {
                    let phase = time * (3.2 + Double(index) * 0.17) + Double(index) * 0.88
                    let edgeScale = index == 0 || index == barCount - 1 ? 0.42 : 1.0
                    let dynamic = (0.28 + abs(sin(phase)) * 0.72) * edgeScale
                    let settled = 0.22 + Double(index % 3) * 0.08
                    let amplitude = isPlaying && !reduceMotion ? dynamic : settled
                    let height = max(3, size.height * CGFloat(amplitude))
                    let rect = CGRect(
                        x: originX + CGFloat(index) * (barWidth + spacing),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(color.opacity(isEmphasized ? 1 : 0.86))
                    )
                }
            }
        }
        .animation(NotchMotionGraph.animation(for: .selection, reduceMotion: reduceMotion), value: isPlaying)
    }
}

@MainActor
private final class CompactArtworkBackgroundModel: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var identity: String?

    func update(
        artwork: NSImage?,
        identifier: String?,
        reduceMotion: Bool
    ) async {
        guard let artwork,
              let sourceData = artwork.tiffRepresentation else {
            image = nil
            identity = nil
            return
        }

        let requestedIdentity = identifier ?? String(sourceData.hashValue)
        if identity == requestedIdentity, image != nil { return }
        let processedData = await CompactArtworkCache.shared.processedImageData(
            sourceData: sourceData,
            identifier: requestedIdentity
        )
        guard !Task.isCancelled,
              let processedData,
              let processedImage = NSImage(data: processedData) else { return }

        if reduceMotion {
            image = processedImage
            identity = requestedIdentity
        } else {
            withAnimation(.easeInOut(duration: 0.30)) {
                image = processedImage
                identity = requestedIdentity
            }
        }
    }
}

private actor CompactArtworkCache {
    static let shared = CompactArtworkCache()
    private var images: [String: Data] = [:]
    private var order: [String] = []
    private let context = CIContext(options: [.cacheIntermediates: true])

    func processedImageData(sourceData: Data, identifier: String) -> Data? {
        if let cached = images[identifier] { return cached }
        guard !Task.isCancelled,
              let input = CIImage(data: sourceData) else { return nil }

        let targetSize = CGSize(width: 760, height: 96)
        let scale = max(
            targetSize.width / input.extent.width,
            targetSize.height / input.extent.height
        )
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let cropRect = CGRect(
            x: scaled.extent.midX - targetSize.width / 2,
            y: scaled.extent.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        let blurred = scaled
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 17])
            .cropped(to: cropRect)
        guard !Task.isCancelled,
              let cgImage = context.createCGImage(blurred, from: cropRect) else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        guard let data = representation.representation(using: .jpeg, properties: [.compressionFactor: 0.76]) else {
            return nil
        }

        images[identifier] = data
        order.removeAll { $0 == identifier }
        order.append(identifier)
        while order.count > 2 {
            let expired = order.removeFirst()
            images.removeValue(forKey: expired)
        }
        return data
    }
}

private extension Color {
    init(_ accent: NowPlayingService.MediaAccent) {
        self.init(red: accent.red, green: accent.green, blue: accent.blue)
    }
}

// MARK: - Expanded controls panel

struct NowPlayingExpandedView: View {
    @EnvironmentObject var nowPlaying: NowPlayingService
    let track: NowPlayingService.Track
    var morphNamespace: Namespace.ID? = nil
    @State private var scrubbedProgress: Double?
    @State private var scrubClearTask: Task<Void, Never>?

    var body: some View {
        let theme = MediaSourceTheme.resolve(for: track)

        return ZStack(alignment: .topLeading) {
            ambientBackground(theme: theme)

            VStack(alignment: .leading, spacing: ExpandedMediaTokens.sectionSpacing) {
                sourceHeader(theme: theme)
                mediaIdentity(theme: theme)
                scrubber(theme: theme)
            }
            .padding(.horizontal, ExpandedMediaTokens.horizontalPadding)
            .padding(.vertical, ExpandedMediaTokens.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onDisappear {
            scrubClearTask?.cancel()
            scrubClearTask = nil
        }
    }

    private func ambientBackground(theme: MediaSourceTheme) -> some View {
        ZStack {
            if let artwork = track.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .scaleEffect(theme.usesWideArtwork ? 1.16 : ExpandedMediaTokens.backgroundScale)
                    .blur(radius: theme.usesWideArtwork ? 28 : ExpandedMediaTokens.backgroundBlur)
                    .saturation(1.18)
                    .opacity(theme.usesWideArtwork ? 0.46 : 0.28)
            }

            LinearGradient(
                colors: [
                    theme.ambientAccent.opacity(theme.usesWideArtwork ? 0.26 : 0.18),
                    Color.black.opacity(0.32),
                    Color.black.opacity(0.72),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func sourceHeader(theme: MediaSourceTheme) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                MediaSourceLogoView(logo: theme.logo)
                Text(theme.name)
            }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(theme.accent.opacity(0.12), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(theme.accent.opacity(0.2), lineWidth: 0.75)
                }
            Spacer()
            EQBarsView(isAnimating: track.isPlaying, primaryColor: theme.accent)
                .frame(width: 16, height: 11)
                .matchedGeometry(id: "music-eq", in: morphNamespace)
                .opacity(track.isPlaying ? 0.9 : 0.32)
            Circle()
                .fill(track.isPlaying ? theme.accent : .white.opacity(0.3))
                .frame(width: 5, height: 5)
            Text(track.isPlaying ? "Playing" : "Paused")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private func mediaIdentity(theme: MediaSourceTheme) -> some View {
        if let video = track.videoPresentation {
            videoIdentity(video, theme: theme)
        } else {
            audioIdentity(theme: theme)
        }
    }

    private func audioIdentity(theme: MediaSourceTheme) -> some View {
        HStack(alignment: .center, spacing: ExpandedMediaTokens.identitySpacing) {
            artwork(theme: theme)
            VStack(alignment: .leading, spacing: 0) {
                Text(track.title)
                    .font(.system(size: theme.usesWideArtwork ? 20 : 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .contentTransition(.interpolate)
                Text(primaryMetadata(theme: theme))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .padding(.top, 5)
                if let tertiaryMetadata {
                    Text(tertiaryMetadata)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                Spacer(minLength: 7)
                controlsRow(theme: theme)
            }
            Spacer(minLength: 4)
        }
        .frame(height: 112)
    }

    private func videoIdentity(
        _ video: NowPlayingService.VideoPresentation,
        theme: MediaSourceTheme
    ) -> some View {
        HStack(alignment: .center, spacing: ExpandedMediaTokens.identitySpacing) {
            videoArtwork(video, theme: theme)

            VStack(alignment: .leading, spacing: 0) {
                Text(video.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .contentTransition(.interpolate)

                if let subtitle = video.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.top, 4)
                        .contentTransition(.interpolate)
                }

                HStack(spacing: 6) {
                    if let episodeLabel = video.episodeLabel {
                        Text(episodeLabel)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(theme.accent.opacity(0.13), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(theme.accent.opacity(0.22), lineWidth: 0.75)
                            }
                    }

                    if let genre = video.genre, !genre.isEmpty {
                        Text(genre)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 6)

                Spacer(minLength: 5)
                controlsRow(theme: theme, cinematic: true)
            }

            Spacer(minLength: 0)
        }
        .frame(height: ExpandedMediaTokens.wideArtworkSize.height)
    }

    private func videoArtwork(
        _ video: NowPlayingService.VideoPresentation,
        theme: MediaSourceTheme
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = track.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [theme.accent.opacity(0.28), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.58)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(spacing: 6) {
                platformArtworkBadge(theme: theme)
                Spacer(minLength: 4)
                Text(video.isEpisode ? "EPISODE" : "FILM")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 8)
        }
        .frame(
            width: ExpandedMediaTokens.wideArtworkSize.width,
            height: ExpandedMediaTokens.wideArtworkSize.height
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: ExpandedMediaTokens.wideArtworkRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ExpandedMediaTokens.wideArtworkRadius,
                style: .continuous
            )
            .stroke(.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: theme.accent.opacity(0.2), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.44), radius: 13, y: 8)
        .matchedGeometry(id: "music-art", in: morphNamespace)
    }

    private func artwork(theme: MediaSourceTheme) -> some View {
        let size = theme.usesWideArtwork
            ? ExpandedMediaTokens.wideArtworkSize
            : ExpandedMediaTokens.artworkSize
        let radius = theme.usesWideArtwork
            ? ExpandedMediaTokens.wideArtworkRadius
            : ExpandedMediaTokens.artworkRadius
        return Group {
            if let image = track.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: theme.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: theme.accent.opacity(0.16), radius: 18, y: 7)
        .shadow(color: .black.opacity(0.42), radius: 12, y: 7)
        .matchedGeometry(id: "music-art", in: morphNamespace)
    }

    private func platformArtworkBadge(theme: MediaSourceTheme) -> some View {
        HStack(spacing: 5) {
            MediaSourceLogoView(logo: theme.logo, size: 15)
            Text(theme.name)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(height: 23)
        .background(.black.opacity(0.62), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.75)
        }
    }

    private func scrubber(theme: MediaSourceTheme) -> some View {
        TimelineView(.animation(minimumInterval: AppMotion.FrameInterval.lowFrequency, paused: !track.isPlaying)) { ctx in
            let elapsed = track.elapsed(at: ctx.date)
            let progress = track.progress(at: ctx.date)
            let displayedProgress = scrubbedProgress ?? progress
            let displayedElapsed = track.duration > 0
                ? displayedProgress * track.duration
                : elapsed
            let remaining = max(0, track.duration - displayedElapsed)
            HStack(spacing: 10) {
                Text(format(displayedElapsed))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .monospacedDigit()
                ProgressBar(
                    progress: displayedProgress,
                    primaryColor: theme.accent,
                    isEnabled: track.duration > 0,
                    onScrubChanged: { progress in
                        scrubClearTask?.cancel()
                        scrubClearTask = nil
                        scrubbedProgress = progress
                    },
                    onScrubEnded: { progress in
                        scrubClearTask?.cancel()
                        scrubbedProgress = progress
                        NotchHaptics.perform(.navigation)
                        nowPlaying.seek(to: progress * track.duration)
                        scrubClearTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            guard !Task.isCancelled else { return }
                            scrubbedProgress = nil
                            scrubClearTask = nil
                        }
                    }
                )
                .frame(height: 14)
                Text(track.duration > 0 ? "-\(format(remaining))" : "--:--")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .monospacedDigit()
            }
        }
    }

    private func controlsRow(
        theme: MediaSourceTheme,
        cinematic: Bool = false
    ) -> some View {
        HStack(spacing: cinematic ? 13 : 8) {
            ControlButton(
                symbol: "backward.fill",
                label: "Previous",
                size: cinematic ? 15 : 13,
                prominent: false,
                accent: theme.accent,
                foreground: .white,
                diameter: cinematic ? 39 : nil
            ) {
                NotchHaptics.perform(.navigation)
                nowPlaying.previousTrack()
            }
            ControlButton(
                symbol: track.isPlaying ? "pause.fill" : "play.fill",
                label: track.isPlaying ? "Pause" : "Play",
                size: cinematic ? 19 : 18,
                prominent: true,
                accent: theme.accent,
                foreground: theme.controlForeground,
                diameter: cinematic ? 48 : nil
            ) {
                NotchHaptics.perform(.navigation)
                nowPlaying.togglePlayPause()
            }
            ControlButton(
                symbol: "forward.fill",
                label: "Next",
                size: cinematic ? 15 : 13,
                prominent: false,
                accent: theme.accent,
                foreground: .white,
                diameter: cinematic ? 39 : nil
            ) {
                NotchHaptics.perform(.navigation)
                nowPlaying.nextTrack()
            }
        }
    }

    private func primaryMetadata(theme: MediaSourceTheme) -> String {
        if !track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return track.artist
        }
        return track.album ?? theme.name
    }

    private var tertiaryMetadata: String? {
        guard let album = track.album,
              !album.isEmpty,
              !track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              album != track.artist else { return nil }
        return album
    }

    private var outputDeviceButton: some View {
        Image(systemName: "airpods.gen3")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Sub-components

private struct ProgressBar: View {
    let progress: Double
    let primaryColor: Color
    let isEnabled: Bool
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    private var clampedProgress: CGFloat {
        CGFloat(min(1, max(0, progress)))
    }

    var body: some View {
        GeometryReader { geo in
            let fillWidth = geo.size.width * clampedProgress
            let revealsThumb = (isDragging || isHovering) && isEnabled
            let thumbSize: CGFloat = revealsThumb ? 10 : 6

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 4)
                Capsule(style: .continuous)
                    .fill(primaryColor)
                    .frame(width: max(0, fillWidth))
                    .frame(height: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Color.black.opacity(0.24), radius: 2, x: 0, y: 1)
                    .offset(x: min(max(fillWidth - thumbSize / 2, 0), max(0, geo.size.width - thumbSize)))
                    .opacity(revealsThumb ? 1 : 0)
            }
            .animation(NotchMotionGraph.animation(for: .selection), value: revealsThumb)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        isDragging = true
                        onScrubChanged(progress(for: value.location.x, width: geo.size.width))
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        isDragging = false
                        onScrubEnded(progress(for: value.location.x, width: geo.size.width))
                    }
            )
        }
    }

    private func progress(for locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, locationX / width)))
    }
}

private struct ControlButton: View {
    let symbol: String
    let label: String
    let size: CGFloat
    let prominent: Bool
    let accent: Color
    let foreground: Color
    var diameter: CGFloat? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let resolvedDiameter = diameter
            ?? (prominent ? ExpandedMediaTokens.primaryControlSize : ExpandedMediaTokens.controlSize)

        Button(action: action) {
            ZStack {
                Circle()
                    .fill(background)
                    .frame(
                        width: resolvedDiameter,
                        height: resolvedDiameter
                    )
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(prominent ? foreground : Color.white.opacity(0.86))
                    .offset(x: prominent && symbol == "play.fill" ? 1 : 0)
            }
            .contentShape(Circle())
            .scaleEffect(isHovering ? 1.055 : 1)
            .shadow(color: prominent ? accent.opacity(0.28) : .clear, radius: 9, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(NotchMotionGraph.animation(for: .hover), value: isHovering)
        .accessibilityLabel(label)
        .help(label)
    }

    private var background: Color {
        if prominent {
            return accent.opacity(isHovering ? 1 : 0.92)
        }
        return Color.white.opacity(isHovering ? 0.14 : 0.065)
    }
}

// MARK: - Optional matchedGeometryEffect helper

extension View {
    /// Apply `matchedGeometryEffect` only when a namespace is supplied. Lets the
    /// music views accept an *optional* namespace so they still work standalone
    /// (e.g. in previews) without forcing every callsite to provide one.
    @ViewBuilder
    func matchedGeometry(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Marquee (continuously scrolling song title)

struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 11, weight: .medium, design: .rounded)
    var color: Color = .white.opacity(0.85)
    var pointsPerSecond: Double = 28
    /// Gap between the end of one repetition and the start of the next.
    var gap: CGFloat = 48

    @State private var textWidth: CGFloat = 0
    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let viewportWidth = geo.size.width
            let needsScroll = textWidth > viewportWidth - 1
            ZStack(alignment: .leading) {
                if needsScroll, !reduceMotion {
                    TimelineView(.animation(minimumInterval: AppMotion.FrameInterval.standard)) { ctx in
                        let cycle = textWidth + gap
                        let elapsed = max(0, ctx.date.timeIntervalSince(startDate))
                        let phase = CGFloat(elapsed * pointsPerSecond)
                            .truncatingRemainder(dividingBy: cycle)
                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: -phase)
                    }
                } else {
                    label
                        .frame(width: viewportWidth, alignment: .center)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: viewportWidth, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .background(measurement)
        .onAppear {
            startDate = Date()
        }
        .onChange(of: text) { _, _ in
            startDate = Date()
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Hidden, full-size copy used purely to read the rendered width of `text`.
    private var measurement: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .opacity(0)
            .allowsHitTesting(false)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { textWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, new in textWidth = new }
                }
            )
    }
}

private func makeArtworkGradient(from artwork: NSImage?) -> LinearGradient {
    let baseColor: Color = artwork?.dominantColor() ?? Color.white.opacity(0.18)
    return LinearGradient(
        colors: [
            baseColor.opacity(0.38),
            baseColor.opacity(0.18),
            Color.black.opacity(0.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Artwork Color Extraction

extension NSImage {
    /// Picks a lively artwork color that remains readable against the black
    /// notch. Light colors from the artwork are preferred; dark-only palettes
    /// are gently lifted instead of being replaced with an unrelated color.
    func waveAccentColor() -> Color {
        guard let cgImage = self.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return .white
        }

        let width = 40
        let height = 40
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](
            repeating: 0,
            count: width * height * bytesPerPixel
        )

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .white
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [String: (count: Int, r: CGFloat, g: CGFloat, b: CGFloat)] = [:]

        for pixel in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            let alpha = CGFloat(rawData[pixel + 3]) / 255
            guard alpha > 0.8 else { continue }

            let r = CGFloat(rawData[pixel]) / 255
            let g = CGFloat(rawData[pixel + 1]) / 255
            let b = CGFloat(rawData[pixel + 2]) / 255
            let maximum = max(r, g, b)
            let minimum = min(r, g, b)
            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0

            // Keep pale artwork tones, but discard near-black and flat mid-grey
            // pixels that do not make useful music-player accents.
            guard maximum > 0.08 else { continue }
            guard saturation > 0.08 || maximum > 0.72 else { continue }

            let key = "\(Int(r * 7))-\(Int(g * 7))-\(Int(b * 7))"
            if let existing = buckets[key] {
                buckets[key] = (
                    count: existing.count + 1,
                    r: existing.r + r,
                    g: existing.g + g,
                    b: existing.b + b
                )
            } else {
                buckets[key] = (count: 1, r: r, g: g, b: b)
            }
        }

        let candidates = buckets.values.map { bucket -> ArtworkColorCandidate in
            let count = CGFloat(bucket.count)
            return ArtworkColorCandidate(
                count: bucket.count,
                r: bucket.r / count,
                g: bucket.g / count,
                b: bucket.b / count
            )
        }

        guard !candidates.isEmpty else { return .white }

        let minimumWaveLuminance: CGFloat = 0.18
        if let dominant = candidates.max(by: { $0.count < $1.count }) {
            let originalAccent = dominant.brightened(by: 1.15)
            if originalAccent.luminance >= minimumWaveLuminance {
                return originalAccent.color
            }
        }

        // The artwork's normal dominant color was too dark. Prefer a naturally
        // light tone when one exists, without changing already-readable colors.
        let lightCandidates = candidates.filter {
            $0.luminance >= minimumWaveLuminance
        }
        let pool = lightCandidates.isEmpty ? candidates : lightCandidates
        guard let selected = pool.max(by: { $0.waveScore < $1.waveScore }) else {
            return .white
        }

        var r = selected.r
        var g = selected.g
        var b = selected.b

        // On dark-only covers, preserve the selected hue and progressively mix
        // in white until it has enough luminance to read cleanly on the notch.
        while relativeLuminance(r: r, g: g, b: b) < minimumWaveLuminance {
            r += (1 - r) * 0.08
            g += (1 - g) * 0.08
            b += (1 - b) * 0.08
        }

        return Color(red: r, green: g, blue: b)
    }

    /// Extracts a clean dominant color from the artwork.
    /// Good for dynamic gradients behind music UI.
    func dominantColor() -> Color {
        guard let cgImage = self.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return Color.white.opacity(0.18)
        }

        let width = 40
        let height = 40

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var rawData = [UInt8](
            repeating: 0,
            count: width * height * bytesPerPixel
        )

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Color.white.opacity(0.18)
        }

        context.interpolationQuality = .medium
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        var colorCounts: [String: (count: Int, r: CGFloat, g: CGFloat, b: CGFloat)] = [:]

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel

                let r = CGFloat(rawData[index]) / 255.0
                let g = CGFloat(rawData[index + 1]) / 255.0
                let b = CGFloat(rawData[index + 2]) / 255.0
                let a = CGFloat(rawData[index + 3]) / 255.0

                guard a > 0.8 else { continue }

                let brightness = (r + g + b) / 3.0
                let saturation = max(r, g, b) - min(r, g, b)

                // Ignore boring blacks, whites, and greys.
                guard brightness > 0.12, brightness < 0.88 else { continue }
                guard saturation > 0.12 else { continue }

                // Quantize colors so nearby colors group together.
                let qr = Int(r * 8)
                let qg = Int(g * 8)
                let qb = Int(b * 8)
                let key = "\(qr)-\(qg)-\(qb)"

                if let existing = colorCounts[key] {
                    colorCounts[key] = (
                        count: existing.count + 1,
                        r: existing.r + r,
                        g: existing.g + g,
                        b: existing.b + b
                    )
                } else {
                    colorCounts[key] = (
                        count: 1,
                        r: r,
                        g: g,
                        b: b
                    )
                }
            }
        }

        guard let best = colorCounts.values.max(by: { $0.count < $1.count }) else {
            return Color.white.opacity(0.18)
        }

        let count = CGFloat(best.count)

        let r = min(best.r / count * 1.15, 1.0)
        let g = min(best.g / count * 1.15, 1.0)
        let b = min(best.b / count * 1.15, 1.0)

        return Color(red: r, green: g, blue: b)
    }
}

private struct ArtworkColorCandidate {
    let count: Int
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    var luminance: CGFloat {
        relativeLuminance(r: r, g: g, b: b)
    }

    var saturation: CGFloat {
        let maximum = max(r, g, b)
        guard maximum > 0 else { return 0 }
        return (maximum - min(r, g, b)) / maximum
    }

    var waveScore: CGFloat {
        sqrt(CGFloat(count)) * (0.75 + saturation * 1.4) * (0.8 + luminance)
    }

    var color: Color {
        Color(red: r, green: g, blue: b)
    }

    func brightened(by factor: CGFloat) -> ArtworkColorCandidate {
        ArtworkColorCandidate(
            count: count,
            r: min(r * factor, 1),
            g: min(g * factor, 1),
            b: min(b * factor, 1)
        )
    }
}

private func relativeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
    func linearize(_ component: CGFloat) -> CGFloat {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * linearize(r)
        + 0.7152 * linearize(g)
        + 0.0722 * linearize(b)
}


// MARK: - EQ bars (animated audio indicator)

struct EQBarsView: View {
    let isAnimating: Bool
    var primaryColor: Color = .white
    let barCount: Int = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: AppMotion.FrameInterval.standard, paused: !isAnimating || reduceMotion)) { ctx in
            Canvas { context, size in
                let barGradient = Gradient(stops: [
                    .init(color: primaryColor, location: 0.0),
                    .init(color: primaryColor.opacity(0.72), location: 1.0)
                ])

                let barWidth: CGFloat = 2.2
                let spacing: CGFloat = 2.4
                let usedWidth = CGFloat(barCount) * barWidth
                    + CGFloat(barCount - 1) * spacing
                let leadingX = (size.width - usedWidth) / 2
                let centerY = size.height / 2
                let maxBarHeight = size.height * 0.85
                let minBarHeight: CGFloat = 2
                let now = ctx.date.timeIntervalSinceReferenceDate

                for i in 0..<barCount {
                    let phase = Double(i) * 0.85
                    let frequency = 1.6 + Double(i) * 0.22

                    let normalized: Double
                    if isAnimating, !reduceMotion {
                        let raw = sin(now * frequency + phase)
                        normalized = (abs(raw) * 0.6) + 0.25
                    } else {
                        normalized = 0.32
                    }

                    let barHeight = max(
                        minBarHeight,
                        maxBarHeight * CGFloat(normalized)
                    )

                    let x = leadingX + CGFloat(i) * (barWidth + spacing)
                    let y = centerY - barHeight / 2

                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: barWidth,
                        height: barHeight
                    )

                    let path = Path(
                        roundedRect: rect,
                        cornerRadius: barWidth / 2
                    )

                    context.fill(
                        path,
                        with: .linearGradient(
                            barGradient,
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    )
                }
            }
        }
        .shadow(color: primaryColor.opacity(0.42), radius: 3)
    }
}

#if DEBUG
@MainActor
private struct NowPlayingCanvasPreview: View {
    @StateObject private var nowPlaying = NowPlayingService()
    let isExpanded: Bool
    var track = NowPlayingPreviewFixtures.appleMusicTrack

    var body: some View {
        Group {
            if isExpanded {
                NowPlayingExpandedView(track: track)
                    .frame(
                        width: NowPlayingMetrics.expandedSize.width,
                        height: NowPlayingMetrics.expandedSize.height
                    )
            } else {
                NowPlayingCollapsedView(
                    track: track,
                    isHovering: true
                )
                .frame(width: NowPlayingMetrics.collapsedWidth, height: 56)
            }
        }
        .environmentObject(nowPlaying)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(24)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }
}

@MainActor
private enum NowPlayingPreviewFixtures {
    static let artwork = NSImage(
        size: NSSize(width: 160, height: 160),
        flipped: false
    ) { rect in
        NSGradient(colors: [
            NSColor(red: 0.04, green: 0.08, blue: 0.20, alpha: 1),
            NSColor(red: 0.20, green: 0.44, blue: 0.92, alpha: 1),
            NSColor(red: 0.91, green: 0.50, blue: 0.72, alpha: 1)
        ])?.draw(in: rect, angle: -45)
        return true
    }

    static let appleMusicTrack = NowPlayingService.Track(
        title: "Midnight City",
        artist: "M83",
        album: "Hurry Up, We're Dreaming",
        artwork: artwork,
        duration: 244,
        elapsedAtTimestamp: 86,
        timestamp: Date(),
        playbackRate: 1,
        sourceApplicationName: "Music",
        sourceBundleIdentifier: "com.apple.Music"
    )

    static let spotifyTrack = NowPlayingService.Track(
        title: "Instant Crush",
        artist: "Daft Punk feat. Julian Casablancas",
        album: "Random Access Memories",
        artwork: artwork,
        duration: 337,
        elapsedAtTimestamp: 128,
        timestamp: Date(),
        playbackRate: 1,
        sourceApplicationName: "Spotify",
        sourceBundleIdentifier: "com.spotify.client"
    )

    static let appleTVTrack = NowPlayingService.Track(
        title: "Severance",
        artist: "Defiant Jazz",
        album: "Season 2 · Episode 7",
        artwork: artwork,
        duration: 3_126,
        elapsedAtTimestamp: 1_042,
        timestamp: Date(),
        playbackRate: 1,
        sourceApplicationName: "TV",
        sourceBundleIdentifier: "com.apple.TV"
    )
}

#Preview("Now Playing - Collapsed") {
    NowPlayingCanvasPreview(isExpanded: false)
}

#Preview("Now Playing - Expanded") {
    NowPlayingCanvasPreview(isExpanded: true)
}

#Preview("Now Playing - Spotify") {
    NowPlayingCanvasPreview(
        isExpanded: true,
        track: NowPlayingPreviewFixtures.spotifyTrack
    )
}

#Preview("Now Playing - Apple TV") {
    NowPlayingCanvasPreview(
        isExpanded: true,
        track: NowPlayingPreviewFixtures.appleTVTrack
    )
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
