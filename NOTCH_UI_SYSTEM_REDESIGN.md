# NotchLand Unified Notch UI System Redesign

## Purpose

This document is the migration contract for rebuilding the complete notch UI as one hardware-integrated system. The supplied `redesign.png` reference is the visual baseline. The implementation must never become a floating card below the notch and no content may overlap the physical camera housing.

## Current architecture

- `WindowManager` owns one transparent, borderless `NotchPanel`, pins its maximum envelope to the top of the selected display, routes hover and drag/drop, and hosts `FloatingNotchView`.
- `FloatingNotchView` is the current state router. It resolves string branch keys, calculates a per-branch visible size, draws the shell, and swaps media, call, HUD, file-drop, wallet, calendar, onboarding, and widget content.
- `AppState` currently exposes only `isExpanded` and `isHovering`. Hover may directly schedule full expansion.
- `NotchSettings` persists raw collapsed/expanded dimensions and appearance preferences.
- `ExpandedNotchWidgetHost` switches between media, calendar, files, wallet, timeline, shortcuts, timer, notes, tasks, clipboard, actions, and mirror.
- `NowPlayingService.Track` already normalizes most media metadata and provides a compact presentation. Source detection covers Apple Music, Spotify, Apple TV, YouTube, Netflix, Disney+, and unknown sources.
- Calls and Bluetooth/audio-device events are separate presentation paths (`CallOverlayView` and `LiveActivityChipView`) with their own dimensions and spacing.

## Current panel files

- `NotchLand/WindowManager.swift`: panel lifecycle, display selection, top anchoring, maximum envelope, hit testing, screenshot sharing, drag/drop.
- `NotchLand/FloatingNotchView.swift`: shell, state routing, visible-size calculation, content transitions, click zones.
- `NotchLand/AppState.swift`: hover/expanded runtime state.
- `NotchLand/NotchSettings.swift`: persistent preferences.
- `NotchLand/NotchWidgetView.swift`: large widget host and widget rail.

## Current shape implementation

- The standard surface uses one `NotchDropShape` for fill, clip, content shape, and SwiftUI shadow.
- A second `CalendarCountdownNotchShape` creates a special asymmetric compact branch.
- `NotchShape` also remains in the source for previews/legacy geometry.
- The NSPanel has no AppKit shadow; SwiftUI draws it, which is correct, but geometry and shadow tuning are still branch-specific.
- The center hardware region is sometimes represented as spacing in individual views, but there is no mandatory shared exclusion-zone layout primitive.

## Current animation implementation

- `NotchMotionGraph` defines named motion roles, but durations range across several springs and some feature views add their own local animations.
- `FloatingNotchView` uses a branch handoff with scale and blur plus branch-specific size changes.
- `AppState` hover can open the full expanded view after a delay; there is no explicit compact → medium → large state machine.
- Width and height are often changed as one size value, so expansion order is not guaranteed.

## Current activity states

- Media: compact and expanded.
- Calls: incoming, connecting, active, ended, missed.
- Audio devices: a connected live-activity event; connecting/disconnecting/low-battery require a normalized accessory phase.
- Calendar, clipboard, shortcuts, file shelf, timer, reminders/tasks, wallet, and other tools: primarily expanded widget content plus several feature-specific compact chips.
- System alerts: HUD, battery, focus, screen lock, wallet contribution, event countdown, live activity.

## Known inconsistencies

- Each activity defines its own dimensions, typography, padding, and control scale.
- Branch keys and size calculation are duplicated between `FloatingNotchView` and `WindowManager`.
- Compact media is wide but not driven by a user-selectable global size.
- Call layouts are too tall and put content below the hardware region instead of consistently using left/right wings.
- Bluetooth activity is modeled as a generic live activity and cannot express all required phases.
- Expanded utility views have independent card styling.
- Some views approximate a notch gap locally; enforcement is not architectural.

## Target visual system

Every state uses a single set of tokens and a single three-region layout:

`[ left content wing ] [ hardware exclusion zone ] [ right content wing ]`

The exclusion zone is always empty, black, noninteractive, and at least as wide as the detected hardware notch. On a display without a notch, the same layout uses a configurable virtual exclusion zone.

The shell is near-black with restrained translucent material, a one-pixel low-opacity stroke, content-derived tint only where useful, and a soft path-following shadow. Typography uses SF Pro and an 8-point spacing grid. Interactive controls alone may receive circular hover surfaces.

## Shared architecture

- `NotchPresentationState`: idle, hover, compact, medium, expanded.
- `NotchSize`: small, medium, large; persisted in `NotchSettings`.
- `NotchActivityType`: media, call, bluetooth, calendar, clipboard, shortcuts, fileShelf, timer, reminder, systemStatus.
- `NotchActivityPresentation`: shared identity/title/subtitle/accent protocol.
- `NotchLayoutMetrics`: the single source for surface sizes, wing padding, exclusion width, radii, typography, and hover deltas.
- `NotchTheme`: fill, stroke, shadow, text hierarchy, and contrast behavior.
- `NotchAnimationProfile`: one non-overshooting spring plus staged width/height/content timings.
- `NotchHardwareLayout`: a reusable left/exclusion/right SwiftUI container. Compact and medium activities must render through it.

Business data remains owned by existing controllers. Renderers adapt that data into shared presentation values; they do not duplicate detection or control logic for each size.

## Target size metrics

| Size | Height | Width | Bottom radius | Content padding |
| --- | ---: | ---: | ---: | ---: |
| Small | 48 pt | 420–560 pt | 22 pt | 16 pt |
| Medium | 78 pt | 600–760 pt | 28 pt | 22 pt |
| Large | 318 pt default, 220–420 pt allowed | 700–920 pt | 34 pt | 28 pt |

The physical/virtual exclusion width is clamped to 176–238 pt. It remains empty for the full height intersecting the hardware notch. Large content may flow below the hardware housing after the top exclusion band.

## Shape strategy

1. Keep one top-anchored transparent NSPanel envelope.
2. Use one canonical animated shell path for fill, clip, hit testing, border, and shadow silhouette.
3. Draw black behind the complete top attachment band.
4. Put content in `NotchHardwareLayout`; it never receives the center region as usable space.
5. Remove branch-specific shell paths after each activity has migrated.
6. Never add shadow to `NSHostingView` or the rectangular panel.

## Motion strategy

- Hover: 140 ms restrained preview, +12 pt each side and +3 pt height.
- Compact → medium: width phase first (170 ms), height phase second (210 ms), then content (190 ms).
- Medium → large: 260 ms staged transition.
- Collapse: secondary content fade, height collapse, width collapse in 220 ms total.
- Top anchor remains fixed. No panel recreation and no AppKit frame animation during state transitions.
- Reduce Motion replaces geometry springs with short opacity transitions and immediate staged geometry.
- Repeating waveform/device activity is isolated from the full presentation model and stops off-screen.

## Performance risks and controls

- Artwork blur/color extraction: keep the existing async cache and update only when the artwork identifier changes.
- High-frequency playback time: isolate timeline updates to progress labels/indicators.
- Waveforms: use one lightweight timeline local to the visible view and freeze when paused or hidden.
- Size computation: move duplicated branch calculations to shared metrics rather than `GeometryReader` or repeated measurement.
- Rapid activity changes: cancel stale staged-transition tasks and preserve the shell identity.

## Files to modify

- `NotchLand/NotchDesignSystem.swift`
- `NotchLand/NotchSettings.swift`
- `NotchLand/AppState.swift`
- `NotchLand/AppearanceSettingsView.swift`
- `NotchLand/FloatingNotchView.swift`
- `NotchLand/WindowManager.swift`
- `NotchLand/NowPlayingView.swift`
- `NotchLand/NowPlayingService.swift`
- `NotchLand/CallOverlayView.swift`
- `NotchLand/AudioDeviceActivitySource.swift`
- `NotchLand/LiveActivityChipView.swift`
- `NotchLand/NotchWidgetView.swift`
- `NotchLand/CalendarNotchView.swift`
- `NotchLand/ClipboardShelfView.swift`
- `NotchLand/ShortcutsBridgeView.swift`
- focused tests and preview/snapshot fixtures under `NotchLandTests/`

New focused source files may be introduced for shared geometry or presentation adapters; the Xcode project uses a file-system-synchronized source group, so they are included automatically.

## Files not to modify

- MediaRemote helper protocol and system metadata transport unless a verified metadata defect requires it.
- Face unlock/biometric enrollment and privacy implementation.
- Wallet transaction detection.
- Updater and Sparkle integration.
- Onboarding content and unrelated settings sections.
- File persistence/business controllers except where a shared presentation adapter is required.

## Migration plan

### Phase 1 — foundation

Add shared design tokens, persistent size selection, presentation/activity enums, canonical metrics, mandatory hardware exclusion layout, external-display virtual exclusion setting, and stable top-anchor geometry.

### Phase 2 — compact activities

Move compact media, incoming/active/ended calls, and Bluetooth/AirPods phases to the shared left/exclusion/right renderer.

### Phase 3 — medium activities

Add click-to-medium behavior and richer media/call/Bluetooth layouts without opening the entire widget hierarchy.

### Phase 4 — large content

Rebuild large media, calendar, clipboard, and shortcuts with the shared theme, spacing, rails, and top-attached shell.

### Phase 5 — unified motion

Implement width-first/height-second staged state changes, restrained hover, reverse-order collapse, interruption continuity, and Reduce Motion behavior.

### Phase 6 — quality

Remove duplicate sizing/animation paths, audit accessibility, optimize artwork and waveform work, verify external displays, run tests/build, and capture a visual matrix for every state and size.

## Testing and visual QA

- Unit tests for size persistence, exclusion width, layout metrics, media source identity, accessory state, and presentation transitions.
- Rapid play/pause, track change, call phase, device phase, hover, and drag/drop stress checks.
- Screenshot matrix: small/medium/large media for all sources; incoming/active/ended call; every AirPods phase; calendar; clipboard; shortcuts; hardware-notch and external-display modes.
- Pixel-level checks: top attachment, exclusion-zone emptiness, bottom-corner shadow silhouette, one-pixel stroke, title truncation, and control alignment.

## Rollback plan

Each phase is isolated behind shared models and can be reverted independently. Existing controllers and source-detection logic remain intact. During migration, legacy views remain available until their replacement passes build/tests and visual QA. If a phase regresses runtime behavior, revert its focused source changes and restore the previous branch renderer while retaining already validated foundation types.

## Repository checkpoint note

The supplied workspace currently contains no `.git` directory, so phase commits cannot exist until local version control is initialized. No existing history will be fabricated. A baseline/checkpoint must be created before phase commits can be recorded.
