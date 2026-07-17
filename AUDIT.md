# MacFlow technical, visual, UX and performance audit

Audit date: 2026-07-17  
Scope: the complete `NotchLand` app target, `NotchLandTests`, AppKit window lifecycle,
SwiftUI presentation, wallpaper runtime, MouseFree, accessibility-backed activities,
onboarding, preferences and developer tooling.

## Method and evidence

- Static inspection of 29,139 lines across 90+ Swift source files.
- Search for animation ownership, `GeometryReader`, timers, `Task` lifecycles,
  event monitors, notification observers, display APIs, force casts and force unwraps.
- Architecture tracing from `AppDelegate`/`AppRuntime` through controllers,
  `WindowManager`, `FloatingNotchView` and module views.
- Debug build, Xcode Analyze and the complete automated test suite.
- Current automated baseline: 152 tests in 26 suites pass.

This audit does **not** claim Instruments results yet. Time Profiler, SwiftUI
Instrument, Core Animation Hitches, Allocations, Leaks and Energy Log require a
separate interactive profiling pass against a running signed build.

## Executive summary

No currently reproducible P0 crash or data-loss defect was confirmed by the
static audit and automated suite. The main systemic risk is architectural:
presentation priority, geometry, animation phase and hit testing have historically
been derived in different layers. A shared presentation resolver was introduced,
but geometry ownership and motion observability still need to be made explicit.

The largest remaining product risks are multi-display notch ownership, the lack
of a formal transition state machine, high-frequency animated surfaces and very
large SwiftUI/AppKit files that make regressions difficult to isolate.

## P0 — crash, data loss, freeze

### P0 status: no confirmed open P0

The former high-risk areas have defensive implementations:

- file restoration and metadata work are detached from the UI actor;
- wallpaper scene replacement keeps old renderers alive until new renderers are ready;
- event monitors and main WindowManager observers are removed in `deinit`;
- wallpaper transition, automation and visibility tasks are cancelled in `stop()`;
- system accessibility scanning is shared and adaptive rather than duplicated at
  high frequency.

Verification still required before release:

- Address Sanitizer run with repeated file/folder/video drops;
- Thread Sanitizer run while rapidly changing media, calls and wallpapers;
- Leaks run after at least 100 notch expand/collapse cycles;
- large cloud-file and multi-monitor drag/drop test.

## P1 — major functional or UX defects

### P1-01 — notch runtime is single-display

- **Location:** `WindowManager.swift` (`notchPanel`, `resolvedScreen(for:)`).
- **Cause:** one `NSPanel` is attached to the first detected hardware-notch display.
- **Symptom:** the app cannot maintain independent notch runtimes, offsets or sizes
  on multiple enabled displays; hot-plug only relocates the single panel.
- **Solution:** introduce `DisplayCoordinator` and one `NotchDisplayRuntime` per
  enabled stable display ID. Reuse one shared presentation model, but keep window
  ownership per display.
- **Verify:** internal-only, main-display, selected and all-display policies;
  hot-plug, resolution, scaling and menu-bar display changes without recreating
  unaffected windows.

### P1-02 — transition legality is still distributed across booleans

- **Location:** `AppState.swift`, `FloatingNotchView.swift`, call/drop/activity
  controllers.
- **Cause:** `isExpanded`, `isHovering`, drop visibility and controller states can
  change independently. The resolver chooses a winner, but does not define legal
  transitions or restoration of the interrupted state.
- **Symptom:** rapid call/drop/media/hover sequences can interrupt one another in
  ways that are visually valid but semantically ambiguous.
- **Solution:** add a reducer-style `NotchPresentationMachine` with explicit state,
  event, priority, interruption and return-state rules. Keep feature business logic
  in its controllers.
- **Verify:** table-driven tests for every legal transition, rapid interruption,
  call-ended timeout, drag cancellation and previous-state restoration.

### P1-03 — geometry needs a single named owner

- **Location:** `NotchDesignSystem.swift`, `FloatingNotchView.swift`,
  `WindowManager.swift`.
- **Cause:** the shared resolver currently combines presentation priority and
  geometry calculations; call/media/widget preferred sizes are assembled at both
  integration points.
- **Symptom:** future module changes can again make the rendered shell and AppKit
  hit frame disagree, especially during Small/Medium/Large changes.
- **Solution:** split priority resolution from a single `NotchLayoutCoordinator`.
  Modules provide semantic content requests; only the coordinator returns final
  shell size, shoulder radius and top-center anchor geometry.
- **Verify:** identical coordinator snapshot is consumed by rendering and hit
  testing; regression tests for every activity and density.

### P1-04 — multi-display policy is not user-configurable

- **Location:** `NotchSettings.swift`, notch settings UI, `WindowManager.swift`.
- **Cause:** no persisted internal/main/selected/all display policy exists.
- **Symptom:** users cannot control where virtual notches appear and cannot tune
  per-display size or offset.
- **Solution:** add a stable display configuration model after `DisplayCoordinator`
  exists; do not store transient `NSScreen` objects.
- **Verify:** persistence across relaunch and graceful fallback when a selected
  display is disconnected.

## P2 — visual inconsistency, lag, incorrect motion

### P2-01 — motion is not observable

- **Location:** `AppMotion.swift`, `NotchMotionGraph`, developer settings.
- **Cause:** animations have semantic curves but no runtime name, reason, phase or
  render instrumentation.
- **Symptom:** competing state changes look like unexplained jumps and cannot be
  diagnosed from the debug UI.
- **Solution:** add a DEBUG-only Motion Debugger with named events, duration,
  current phase, reason and redraw count. Instrument the notch coordinator first,
  then migrate other critical surfaces.
- **Verify:** rapid hover/media/call/drop changes show ordered, interruptible events;
  disabling the debugger has zero production behavior.

### P2-02 — several animation clocks can be active simultaneously

- **Location:** `NowPlayingView.swift` waveform, scrubber, marquee and visualizer;
  `WallpaperSceneNotchView.swift`.
- **Cause:** separate `TimelineView` instances run at 24, 30 and 60 Hz.
- **Symptom:** expanded media with marquee/waveform can cause avoidable rendering
  load, especially alongside animated wallpaper.
- **Solution:** pause every clock when hidden or inactive, cap nonessential motion
  at 24–30 Hz and share a lightweight phase source where surfaces coexist.
- **Verify:** SwiftUI Instrument invalidation counts and Energy Log at idle,
  paused media and active media.

### P2-03 — large view/controller files obscure invalidation boundaries

- **Location:** `NowPlayingView.swift` (1,891 lines), `FloatingNotchView.swift`
  (1,778), `WindowManager.swift` (1,386), `ScenesSettingsView.swift` (960),
  `HUDController.swift` (870).
- **Cause:** presentation composition, state transitions and helper components are
  colocated in monolithic files.
- **Symptom:** small state changes are harder to reason about and reviewers cannot
  easily see which subtree should invalidate.
- **Solution:** extract by responsibility, not by individual row: shell geometry,
  transition orchestration, activity renderer and debug instrumentation.
- **Verify:** no business-logic duplication, stable view identities and unchanged
  snapshot/model tests.

### P2-04 — selected widget state has two integration paths

- **Location:** `FloatingNotchView` uses `@AppStorage`; `WindowManager` reads
  `UserDefaults.standard` directly.
- **Cause:** the render and hit-test layers do not consume one typed selection
  source.
- **Symptom:** a same-run selection change can briefly produce an old expanded
  hit frame.
- **Solution:** move selected widget into a typed observable presentation model
  injected into both layers.
- **Verify:** switch widgets during expansion and assert identical layout snapshots.

### P2-05 — Swift concurrency warnings remain in system call actions

- **Location:** `SystemCallActivitySource.swift` answer/decline closures.
- **Cause:** non-Sendable function values are converted to `@MainActor @Sendable`
  closures.
- **Symptom:** currently a build warning; under stricter Swift 6 checking this can
  become an error or conceal actor misuse.
- **Solution:** make the action handle explicitly `Sendable` where safe or bridge
  invocation through a MainActor-owned method.
- **Verify:** build with complete concurrency checking and run answer/decline tests.

### P2-06 — performance validation is incomplete

- **Location:** whole app runtime.
- **Cause:** automated tests verify logic but not frame pacing, allocations or idle
  energy.
- **Symptom:** visual smoothness claims cannot yet be quantified.
- **Solution:** add reproducible Instruments templates/scenarios and record baseline
  thresholds in `CHANGELOG_REDESIGN.md`.
- **Verify:** Time Profiler, SwiftUI, Hitches, Allocations, Leaks and Energy Log on
  the 13-inch MacBook Air target hardware.

## P3 — polish and maintainability

### P3-01 — design tokens are not yet universal

- **Location:** legacy feature views, especially media and notch-specific views.
- **Cause:** many historic custom font sizes, paddings and opacity values predate
  `MacFlowDesignSystem`.
- **Symptom:** small typographic and spacing differences remain between modules.
- **Solution:** migrate opportunistically while editing a surface; do not perform a
  risky global repaint.
- **Verify:** Light/Dark, Increase Contrast, Reduce Transparency and long localized text.

### P3-02 — DEBUG compilation conditions are inconsistent

- **Location:** navigation uses `#if DEBUG`; `DebugSettingsView` uses
  `NOTCHLAND_ENABLE_DEBUG_UI`.
- **Cause:** two independent flags describe one developer feature.
- **Symptom:** a custom Debug configuration can expose navigation without compiling
  the destination view, or hide tooling unexpectedly.
- **Solution:** define one project compilation condition and use it everywhere.
- **Verify:** Debug, Release and test build matrices.

### P3-03 — force-unwrapped static URL defaults should be made explicit

- **Location:** `WalletContributionController.swift` default API base URLs.
- **Cause:** compile-time URL literals use `URL(string:)!`.
- **Symptom:** literals are currently valid, but the pattern weakens the no-force-
  unwrap rule and makes future editing unsafe.
- **Solution:** central validated endpoint constants or non-failable URL construction.
- **Verify:** endpoint unit tests.

### P3-04 — UI and visual regression coverage is incomplete

- **Location:** test target.
- **Cause:** strong model tests exist, but sidebar collapse, real panel anchoring,
  display hot-plug and final rendered screenshots are not automated.
- **Symptom:** layout regressions can pass all unit tests.
- **Solution:** add focused UI tests and deterministic rendered snapshot fixtures.
- **Verify:** Small/Medium/Large, Light/Dark, long text, Reduce Motion and external
  display fixtures in CI-capable environments.

## Implementation order

1. Split `NotchPresentationResolver` from `NotchLayoutCoordinator` and add layout snapshots.
2. Add DEBUG Motion Debugger and instrument notch branch/size/hover transitions.
3. Add `NotchPresentationMachine` transition tests.
4. Introduce `DisplayCoordinator`, then multi-display runtimes and preferences.
5. Profile and reduce unnecessary animation clocks.
6. Continue module polish and UI/snapshot coverage.

## Release gate

Do not mark the complete audit roadmap finished until interactive Instruments
profiling and physical multi-display tests have been performed. Automated build,
Analyze and unit tests are necessary but not sufficient evidence for 60 fps,
memory-leak freedom or low idle CPU.
