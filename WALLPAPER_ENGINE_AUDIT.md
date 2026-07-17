# MacFlow Wallpaper Engine — architecture audit

Date: 2026-07-17

## Scope and current architecture

The current wallpaper path is native and intentionally data-only:

```text
ScenesSettingsView / drag-and-drop / open URL
    -> WallpaperSceneController
        -> WallpaperSceneLibrary
            -> app-owned Assets, Thumbnails and library.json
        -> WallpaperPerformanceMonitor
        -> DisplayCoordinator
        -> one WallpaperSceneWindow per selected NSScreen
            -> WallpaperSceneRenderView
                -> CALayer for still images
                -> AVQueuePlayer + AVPlayerLooper + AVPlayerLayer for video
```

Selection is persisted by `WallpaperSceneController`. A scene switch creates a replacement
window for every target display, keeps the previous windows in `retiringWindows`, and fades
between the two sets. Still images are decoded away from the main actor. Video thumbnails,
file copies, package validation and checksums also run away from the main actor. Packages are
non-executable and reject traversal, symlinks, unexpected files, oversized manifests/assets
and checksum mismatches.

Runtime visibility currently consists of one global fullscreen Boolean. It is refreshed from
WindowServer metadata every 1.25 seconds and pauses every video renderer together. Low Power
Mode and thermal pressure select an effective performance profile, but the renderer primarily
uses that profile to set `preferredMaximumResolution`.

## Ten highest-priority technical problems

| Priority | Problem | Severity | Main impact |
| --- | --- | --- | --- |
| 1 | Every display owns an independent `AVQueuePlayer` and decoder, even for the same scene. | High | CPU, GPU, memory, energy |
| 2 | Video calls its readiness callback immediately after creating `AVPlayerLayer`; no displayed frame has been confirmed. | Critical | Black flashes, transition stutter |
| 3 | Fullscreen state is global rather than per display; partially covered, covered, sleeping and disconnected states are not modeled. | High | Energy, incorrect pause behavior |
| 4 | Performance profiles do not provide a complete render budget. Frame rate, transition strategy, preload, HDR and decoder lifetime are not policy-driven. | High | CPU/GPU/energy, predictability |
| 5 | Crossfade always allocates a second full renderer set when Reduce Motion is off, including Eco and thermal pressure. | High | Peak memory, decoder contention |
| 6 | The 420 ms readiness timeout can fade to a video window that still has no frame. | Critical | Black frame, brightness jump |
| 7 | `WallpaperSceneController` owns selection, persistence coordination, automation, visibility polling, display lifecycle, playback policy and transitions. | Medium | Race risk, testability |
| 8 | Transition cancellation is generation-based but unmeasured; there is no proof that all replaced renderers and observers were released after rapid switching. | High | Leaks, orphan playback, instability |
| 9 | There is no event-driven record of codec, resolution, player count, first-frame latency, transition duration, dropped frames or pause reason. | High | Optimizations cannot be validated |
| 10 | WindowServer is scanned on a fixed loop even when nothing changes, and its result cannot reduce work per display. | Medium | CPU wakeups, poor multi-display behavior |

### Resource impact summary

- **CPU:** duplicate video decoding per display, fixed WindowServer polling and avoidable dual-decoder transitions.
- **GPU:** simultaneous full-screen layers during every crossfade and rendering video behind fully covered displays.
- **Memory:** multiple decoder frame queues plus old/new window sets during transitions. A 4K BGRA frame alone is roughly 32 MiB before decoder and compositor buffering.
- **Smoothness:** false first-frame readiness is the dominant visible defect. Rapid scene changes can also contend for decoders while previous transitions are retiring.

## Target architecture

```text
WallpaperPlaybackEngine
├── PlaybackSessionPool
│   ├── SharedVideoClock / synchronized video sessions
│   └── StillImageSession
├── DisplayPresentation (window + final layer only)
├── DisplayVisibilityCoordinator
├── RenderBudgetController
├── SceneVariantSelector
└── WallpaperTelemetryMonitor
```

`WallpaperSceneController` remains the product-facing coordinator, but delegates playback,
visibility, budget and diagnostics. `WallpaperSceneWindow` becomes a presentation surface and
does not decide system policy. The same scene on several displays should first share timing and
asset preparation. Decoder sharing must only be adopted after a reliable AVFoundation design is
proven with Instruments.

## Planned files

### First safe phase — measurement

- Create `NotchLand/WallpaperTelemetry.swift`
- Create `NotchLand/WallpaperBenchmark.swift`
- Modify `NotchLand/WallpaperSceneWindow.swift`
- Modify `NotchLand/WallpaperSceneController.swift`
- Modify `NotchLand/DebugSettingsView.swift` (development-only diagnostics)
- Extend `NotchLandTests/WallpaperSceneTests.swift`

### Later phases

- Create `WallpaperPlaybackEngine.swift`, `WallpaperPlaybackSession.swift`
- Create `WallpaperDisplayVisibilityCoordinator.swift`
- Create `WallpaperRenderBudget.swift`, `WallpaperSceneVariantSelector.swift`
- Refactor `WallpaperSceneWindow.swift` into a display presentation
- Extend `WallpaperScene.swift`, `WallpaperScenePackage.swift` and
  `WallpaperSceneLibrary.swift` for compiler variants and posters
- Redesign `ScenesSettingsView.swift` only after runtime behavior is stable

## Small implementation steps

1. Add immutable telemetry snapshots, renderer events and a bounded event log.
2. Read asset metadata asynchronously and cache it per active asset.
3. Instrument renderer creation, item readiness, first displayed frame, access-log drops,
   stop, transition start, animation start, completion and cancellation.
4. Add event-driven benchmark capture with a documented scenario catalog.
5. Expose diagnostics only behind `NOTCHLAND_ENABLE_DEBUG_UI`.
6. Build and run existing plus targeted telemetry tests.
7. Use recorded baselines before extracting playback sessions.
8. Add per-display visibility and a real render budget.
9. Replace false readiness with confirmed first-frame gating and profile-aware transitions.
10. Stabilize hot-plug/multi-display behavior, then add the first Scene Compiler slice.

## macOS API risks and limitations

- An `AVPlayerLayer` is designed around a player presentation path. Reusing one `AVPlayer`
  across multiple layers is not documented as a reliable multi-output decoder-sharing solution.
  The safe fallback is synchronized players with a shared clock/timebase; this still may decode
  more than once.
- `AVPlayerLayer.isReadyForDisplay` is a useful first-visible-frame signal, but readiness can
  regress after seeks or output changes. It must be scoped to a renderer generation and paired
  with item status and a timeout.
- Dropped-frame counts from `AVPlayerItemAccessLog` are stream/access-log metrics and may be
  unavailable or delayed for local files. Diagnostics must show “unavailable”, not zero.
- Public WindowServer metadata does not expose perfect desktop occlusion. Per-display coverage
  will remain a conservative estimate and must avoid private APIs.
- AVFoundation exposes preferences for resolution and peak bit rate, but arbitrary source FPS
  limiting is not a guaranteed player control. A compiler-created lower-FPS variant is the most
  deterministic Eco solution.
- HDR requires compatible source metadata, display EDR capability and a verified output path.
  A profile name alone must never enable it.
- Exact GPU memory and decoder sharing cannot be proven from app-level estimates. Instruments,
  Metal System Trace and Energy Log remain required for benchmark sign-off.

## Phase 2 acceptance baseline

The telemetry phase is complete when a bounded, non-polling diagnostic snapshot reports the
active scene, asset metadata, player/renderer/display counts, readiness per display, first-frame
latency, transition timing, profile, power/thermal state, pause reason, dropped frames when
available and an explicitly labeled decoded-memory estimate. It must not change rendering policy.

## Phase 2 implementation result

Implemented on 2026-07-17:

- event-driven `WallpaperTelemetrySnapshot` with a bounded 96-event history,
- asynchronous asset inspection for codec, resolution, source FPS, estimated bit rate and duration,
- renderer-generation tracking so retiring frames cannot satisfy a new transition,
- KVO diagnostics for player-item status, likely-to-keep-up and `AVPlayerLayer.isReadyForDisplay`,
- access-log dropped-frame capture when AVFoundation makes it available,
- lifecycle counts for renderers, players and displays, including parallel crossfade renderers,
- first-frame, transition animation, completion and cancellation timing,
- selected/effective profile, Low Power Mode, thermal state, playback rate and pause reason,
- explicitly labeled decoded-frame-buffer memory estimate,
- ten reproducible benchmark definitions and an event-driven benchmark result aggregator,
- development-only diagnostics in the existing Debug settings surface,
- four deterministic unit tests covering lifecycle, multi-display readiness isolation, event
  bounds/pause reasons and benchmark aggregation.

This phase deliberately preserves the current crossfade trigger. Video still invokes the legacy
readiness callback at player creation while telemetry independently records the real first frame.
That produces an honest baseline and avoids combining measurement with the behavioral fix. The
next phase can now quantify how often animation starts before `isReadyForDisplay`.
