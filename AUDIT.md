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
- Debug and Release builds, Xcode Analyze and the complete automated test suite.
- Current automated baseline: 164 tests pass with no failures or skips.
- The same 164-test suite passes with Address Sanitizer and Thread Sanitizer.
- A 10-second Time Profiler recording was attached to the current DerivedData
  executable and reported no `potential-hangs` rows during the measured idle window.

This audit claims only the bounded Time Profiler result above. SwiftUI Instrument,
Core Animation Hitches, Allocations, Leaks and Energy Log still require an
interactive profiling pass against a signed build; the command-line Allocations
instrument could not attach to the unsigned Debug process and is not counted as a pass.

## Executive summary

No currently reproducible P0 crash or data-loss defect was confirmed by the
static audit, sanitizers and automated suite. Presentation priority, legal
interruption/restoration, final geometry, display selection and typed widget
selection now have named owners instead of being inferred independently by views.

The largest remaining engineering risks are the size of several legacy SwiftUI /
AppKit files and the absence of automated physical hot-plug, screenshot and
long-running energy/leak coverage.

## Implemented during this audit

- `NotchPresentationResolver` now owns activity priority only.
- `NotchPresentationMachine` classifies initial, replacement, interruption and
  restoration transitions and preserves nested return-state order.
- `NotchLayoutCoordinator` is the single named owner that converts semantic
  activity requests into the final shell size and shoulder radius consumed by
  both SwiftUI rendering and AppKit hit testing.
- the DEBUG-only Motion Debugger records the animation name, surface, duration,
  target state, trigger reason, completion/interruption phase and SwiftUI surface
  update count;
- notch activity, hover and Small/Medium/Large changes, app-section navigation,
  sidebar visibility and wallpaper crossfades now emit named motion events;
- `DisplayCoordinator` owns stable screen snapshots and internal/main/selected/all
  display policy; `WindowManager` maintains one panel per selected display;
- per-display content size and horizontal offset persist without storing `NSScreen`;
- hover ownership is scoped to one display ID, so a pointer cannot animate every
  notch panel at once;
- widget selection is a typed, observable preference shared by rendering, hit
  testing, gestures and File Shelf actions;
- drag hover no longer performs synchronous filesystem existence checks, and
  concurrent drop completion merges atomically without duplicates;
- nonessential animation clocks are capped at 24–30 Hz and pause when hidden,
  paused or Reduce Motion is active;
- compile-time wallet URLs are validated centrally without force unwraps;
- Debug/Release builds, Xcode Analyze, normal/ASan/TSan suites and the bounded
  current-build Time Profiler pass completed after these changes.

The redraw value in Motion Debugger is deliberately a SwiftUI representable
update count for the instrumented surface, not a claim about GPU frames or exact
`body` evaluation count. Frame pacing still belongs in SwiftUI/Core Animation
Instruments.

## Motion map

| Interaction | Purpose | Animated properties | Duration | Curve | Reduce Motion alternative |
| --- | --- | --- | --- | --- | --- |
| Notch activity owner changes | Preserve origin and explain interruption | width/height shell geometry, content opacity | 160–340 ms by semantic role | controlled spring | opacity with 100 ms state change |
| Small/Medium/Large changes | Keep top-center hardware attachment stable | shell width and height | 220 ms | controlled spring | 100 ms ease-out |
| Notch hover preview | Confirm interactivity without opening content | small width/height delta, contrast | 160 ms | interaction spring | 100 ms opacity/contrast |
| Sidebar visibility | Preserve navigation context | split-view column visibility | 220 ms | standard ease-in-out | 100 ms state change |
| Main section navigation | Explain destination change | content fade and 8 pt directional offset | 220 ms | ease-out insertion | opacity only |
| Wallpaper replacement | Show where the new scene replaces the old one | renderer opacity crossfade | 340 ms | emphasized ease-in-out | 100 ms replacement |
| Notch interruption by call/drop | Make priority takeover legible | outgoing content fade, shell resize, incoming content reveal | 160–220 ms | removal then standard spring | direct crossfade |

### Motion categories

1. **System transitions:** notch activity/size changes, app navigation and sidebar
   visibility. These preserve hierarchy and spatial context.
2. **Microinteractions:** notch hover and selection feedback. These confirm that a
   stable object is interactive without moving surrounding layout.
3. **Shared-element transitions:** the physical notch shell remains the same
   identity while its content request changes; no second floating panel is created.
4. **Loading and progress:** unchanged in this phase; existing determinate progress
   remains linear and indeterminate work continues to use native progress UI.
5. **State and confirmation:** wallpaper crossfade and priority interruptions make
   the source and destination of replacement content visible.

## P0 — crash, data loss, freeze

### P0 status: no confirmed open P0

The former high-risk areas have defensive implementations:

- file restoration and metadata work are detached from the UI actor;
- wallpaper scene replacement keeps old renderers alive until new renderers are ready;
- event monitors and main WindowManager observers are removed in `deinit`;
- wallpaper transition, automation and visibility tasks are cancelled in `stop()`;
- system accessibility scanning is shared and adaptive rather than duplicated at
  high frequency.

Automated Address Sanitizer and Thread Sanitizer suites pass. Verification still
required before release certification:

- Leaks/Allocations run after at least 100 notch expand/collapse cycles;
- large cloud-file and physical multi-monitor drag/drop test;
- a signed-build interaction session covering live calls/media/wallpaper changes.

## P1 — major functional or UX defects

### P1-01 — notch runtime is single-display

**Status: resolved in implementation; physical hot-plug validation remains.**

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

**Status: resolved for presentation arbitration.**

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

**Status: resolved.**

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

**Status: resolved in implementation; physical display validation remains.**

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

**Status: resolved for critical surfaces.**

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

**Status: resolved for audited media and wallpaper clocks.**

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

**Status: resolved.**

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

**Status: resolved during this audit.**

- **Location:** `SystemCallActivitySource.swift` answer/decline closures.
- **Cause:** non-Sendable function values are converted to `@MainActor @Sendable`
  closures.
- **Symptom:** currently a build warning; under stricter Swift 6 checking this can
  become an error or conceal actor misuse.
- **Solution:** the immutable accessibility action handle remains explicitly
  `@unchecked Sendable`, while closure creation now goes through a typed
  `@MainActor @Sendable` bridge instead of relying on an unsafe inferred
  conversion.
- **Verify:** Debug and Release builds no longer emit these warnings; existing
  classifier and call-controller tests pass.

### P2-06 — performance validation is incomplete

**Status: partially verified.**

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

**Status: resolved during this audit.**

- **Location:** navigation uses `#if DEBUG`; `DebugSettingsView` uses
  `NOTCHLAND_ENABLE_DEBUG_UI`.
- **Cause:** two independent flags describe one developer feature.
- **Symptom:** a custom Debug configuration can expose navigation without compiling
  the destination view, or hide tooling unexpectedly.
- **Solution:** developer navigation, destination views and Motion Debugger now use
  `NOTCHLAND_ENABLE_DEBUG_UI` consistently.
- **Verify:** Debug tests and both Debug/Release builds pass; the Developer section
  remains absent from Release.

### P3-03 — force-unwrapped static URL defaults should be made explicit

**Status: resolved.**

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

## Completed implementation order

1. Split `NotchPresentationResolver` from `NotchLayoutCoordinator` and add layout tests.
2. Add DEBUG Motion Debugger and instrument notch branch/size/hover transitions.
3. Add `NotchPresentationMachine` and interruption/restoration tests.
4. Introduce `DisplayCoordinator`, multi-display panels, policies and per-display settings.
5. Scope hover by display, reduce animation clocks and harden drag/drop concurrency.
6. Unify typed widget selection and remove unsafe compile-time endpoint unwraps.
7. Run Debug/Release/Analyze, normal/ASan/TSan tests and bounded Time Profiler.

## Release gate

The implementation roadmap is complete. Release certification still requires
interactive signed-build Instruments coverage and physical multi-display/hot-plug
tests. Automated build, Analyze, sanitizers and unit tests are not sufficient
evidence for universal 60 fps, memory-leak freedom or every monitor topology.
