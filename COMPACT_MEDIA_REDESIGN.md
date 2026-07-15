# Compact Media Redesign

## Scope

This change is limited to the compact media state rendered around the MacBook
notch while playback is active. It does not redesign the expanded media player,
widget rail, settings, onboarding, or unrelated activity surfaces.

## Current implementation

- `FloatingNotchView` selects the `collapsed-music` branch and hosts
  `NowPlayingCollapsedView` inside the canonical `NotchDropShape`.
- `FloatingNotchView.currentVisibleSize(for:)` chooses a fixed compact width and
  derives height from the normal hardware-notch height.
- `NowPlayingCollapsedView` currently has separate audio and video layouts.
  Audio renders artwork on the far left and an equalizer on the far right.
  Video renders a source logo, artwork thumbnail, metadata, a hardware-notch
  spacer, equalizer, and play/pause button.
- Hovering is still coupled to the legacy audio marquee and contributes extra
  height in the sizing path.
- The shell fill, mask, hit shape, and SwiftUI shadow already share one
  `NotchDropShape`. The `NSPanel`/`NSHostingView` shadow is disabled.

## Duplicate / incorrect source identity bug

Source presentation is currently assembled inside `NowPlayingView` through
`MediaSourceTheme`. The compact video branch then renders both this source logo
and a separate artwork/fallback view. When artwork is missing, that second view
falls back to a generic TV/video symbol, producing the duplicate identity seen
by the user. Source detection, identity, metadata hierarchy, and presentation
must be normalized before SwiftUI renders the row.

Apple TV must render exactly one Apple TV identity. Netflix and YouTube must not
gain a second generic video icon. Installed native applications may use their
actual `NSWorkspace` application icon; web services use an original compact
brand mark or one SF Symbol fallback.

## Source detection path

1. `MediaRemoteHelper` reads MediaRemote metadata and enriches it with the
   active application's bundle identifier and name.
2. `NowPlayingService.Track.mediaSource` normalizes Apple Music, Spotify,
   Apple TV, YouTube, Netflix, and unknown sources using bundle, application,
   service, and content identifiers.
3. Apple TV may additionally fill missing show/season/episode metadata through
   `TVAppMetadataProvider`.
4. The redesign will expose a normalized `MediaSourceStyle` and
   `CompactMediaPresentation` from the service layer. Compact SwiftUI will
   consume those values without reclassifying the source.

## Artwork availability and caching

`Track.artwork` is decoded and reused by `NowPlayingService` while the media item
is unchanged. The current compact view does not use it as its shell background.

The compact redesign caches a downsampled/blur-ready background per artwork
identity. Processing occurs off the main actor, is cancelled when the item
changes, and publishes only when the latest request completes. SwiftUI will
crossfade between cached images; blur and dominant-color extraction will not be
performed on every waveform frame or body evaluation.

Apple TV streams frequently omit MediaRemote artwork and expose no artwork on
their AppleScript `current track`. For those items, one cached asynchronous
fallback searches the public regional `tv.apple.com` catalog by the exact
episode/movie title, follows the matching official Apple page, reads its
`og:image`, and downloads that still from Apple's `mzstatic.com` CDN. No screen
capture, DRM-frame extraction, or third-party metadata service is used. The
resolved still is written back to `Track.artwork`, so compact blur and expanded
video artwork share the same source.

If artwork is unavailable, the background is near-black with a restrained
source accent glow.

## Target layout

Reference target: latest user-provided compact image.

Single row below the physical camera area:

`[ source identity ] [ primary + secondary metadata ] [ waveform ] [ play/pause ]`

- Width: source/metadata-aware stable target in the 500–550 pt range.
- Height: 64 pt normal, with no hover-driven vertical jump. Clicking expands
  into the existing 580×318 pt widget host.
- The content is split into equal left/right flanks around the calibrated
  hardware-notch width, so metadata and controls never render under the camera.
- Horizontal padding: 15 pt; the 58 pt artwork surface has a 7 pt side inset
  and a 4 pt bottom inset.
- Source identity: one 32–38 pt mark.
- Primary title: 15 pt semibold, one line.
- Secondary metadata: 12 pt, one line.
- Waveform: isolated lightweight 7-bar animation with quiet outer dots.
- Play/pause: icon-only 30–34 pt hit surface; no previous/next controls.
- No artwork card, progress bar, time labels, menus, “Playing” label, or extra
  capsules in compact mode.

## Source-specific content

- Apple TV / Netflix: episode or media title first; season/episode second,
  optionally followed by show name when it fits.
- YouTube: video title first; channel name second.
- Spotify / Apple Music: song title first; artist second.
- Unknown: title first; artist/application fallback second.

## Shape and shadow strategy

Keep `NotchDropShape` as the only outer shell path. `FloatingNotchView` uses it
for fill, clipping, content shape, and SwiftUI shadow while the host panel shadow
is disabled. The reference-specific 58 pt media surface is inset inside this
black structural shell; it carries the blurred artwork and a subtle hairline,
without owning the panel shadow. A black center bridge uses the calibrated
hardware-notch width and rounded lower corners so artwork cannot bleed through
the camera area or detach visually on an external display.

## Animation strategy

- Container width/height continues through the existing top-anchored motion
  graph in `FloatingNotchView`.
- Compact content uses one staged transition: source, metadata, waveform, then
  control, with restrained opacity/offset/scale values.
- Metadata uses content transitions without changing the shell size.
- Artwork background crossfades independently.
- Play/pause uses symbol replacement and a short selection spring.
- Waveform owns the only repeating animation and pauses when playback is paused
  or Reduce Motion is enabled.
- Hover changes content emphasis and shell width/shadow subtly, never opens the
  expanded widget by itself and never changes compact height.

## Accessibility

- Source and full metadata are exposed as one readable group.
- Play/pause has a state-specific label, action, and value.
- Playback state changes use the existing state update without recreating the
  entire view.
- Reduce Motion removes staged movement and freezes the waveform.
- Increase Contrast increases the dark overlay, border, and foreground opacity.

## Performance risks and mitigations

- **Artwork blur/color recomputation:** cache by artwork fingerprint and process
  off-main; cancel stale work.
- **Waveform invalidating the full row:** isolate animation in its own view.
- **Rapid metadata changes resizing the shell:** use stable source-class widths
  and truncate text instead of measuring continuously.
- **Hover rebuilding expanded content:** compact hover remains inside the same
  branch and view identity.
- **Image memory:** cache only the current and immediately previous compact
  background at a small target size.

## Files to modify

- `NotchLand/NowPlayingService.swift`
  - normalized `MediaSourceStyle` and `CompactMediaPresentation`
  - source-specific compact metadata rules
- `NotchLand/NowPlayingView.swift`
  - compact-only layout, cached background renderer, waveform, hover and
    accessibility behavior
  - expanded player code remains functionally unchanged
- `NotchLand/FloatingNotchView.swift`
  - compact media width/height and hover sizing only
- `NotchLand/WindowManager.swift`
  - only if its maximum compact envelope duplicates obsolete media dimensions
- `NotchLandTests/NowPlayingSourceTests.swift`
  - source identity and compact metadata hierarchy tests
- `NotchLandTests/CompactMediaPresentationTests.swift` (if a separate focused
  suite improves clarity)

## Verification matrix

- Apple TV: exactly one Apple TV icon; episode title; `Sx · Ex`.
- Spotify: Spotify identity; song; artist; green accent remains local.
- Netflix: Netflix identity; episode/title; no generic TV icon.
- Apple Music: Music identity; song; artist.
- YouTube: YouTube identity; video; channel.
- Unknown: one fallback identity; title and best secondary metadata.
- Playing/paused, rapid metadata replacement, hover, Reduce Motion, Increase
  Contrast, no-artwork fallback, build, tests, and five source screenshots.
