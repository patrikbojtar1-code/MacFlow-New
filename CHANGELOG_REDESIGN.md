# MacFlow redesign changelog

## 2026-07-17 — Notch geometry ownership and motion diagnostics

### Changed

- Split notch activity selection from geometry calculation.
- Added `NotchLayoutCoordinator` as the canonical owner of visible shell size,
  hardware-attached shoulder geometry and density-dependent layout.
- Made both `FloatingNotchView` and `WindowManager` consume the same coordinator,
  preventing visible layout and AppKit hover/click/drop hit frames from drifting.
- Added a DEBUG-only Motion Debugger to developer settings.
- Added named instrumentation for notch activity changes, hover, content density,
  sidebar visibility, app navigation and wallpaper crossfade.
- Added interruption tracking when a newer event replaces an active animation.
- Added a lightweight surface-update probe that remains outside Release UI.
- Replaced inferred non-Sendable call action closures with an explicit
  MainActor/Sendable accessibility action bridge.
- Unified developer navigation and tooling under
  `NOTCHLAND_ENABLE_DEBUG_UI` so Release cannot expose a partial debug surface.

### Verification

- Debug build: passed.
- Release build: passed.
- Xcode Analyze: passed.
- Complete Xcode test action: 153 passed, 0 failed, 0 skipped.
- Canonical geometry regression tests cover priority, wallet/drop sizing and
  activity-specific shoulder radius.
- Motion Debugger tests cover interruption, reason and redraw accounting when the
  developer compilation condition is enabled.

### Known open risks

- Motion Debugger counts instrumented SwiftUI surface updates. Exact FPS, hitches,
  allocations, leaks and idle energy still require an interactive Instruments pass.
- Multi-display runtime and formal presentation transitions were intentionally
  deferred to the completion phase documented below.

## 2026-07-17 — State, display and stability completion

### Changed

- Added `NotchPresentationMachine` with explicit priorities, nested interruptions
  and deterministic restoration of the previous activity.
- Added `DisplayCoordinator` with stable display snapshots and persisted
  internal/main/selected/all display policies.
- Replaced the single notch panel with one managed panel per selected display,
  including per-display Small/Medium/Large density and horizontal offset.
- Scoped hover ownership and hit-frame expansion to the display under the pointer.
- Unified selected-widget state under `WidgetPreferencesController`; views,
  gestures, File Shelf and WindowManager no longer read the same UserDefaults key
  through competing paths.
- Cached drag pasteboard payloads, removed filesystem access from drag hover and
  made concurrent File Shelf drops merge without duplicates.
- Capped decorative media/wallpaper timelines at 24–30 Hz and paused inactive or
  Reduce Motion clocks.
- Replaced force-unwrapped wallet endpoint defaults with validated constants and
  exact Decimal values.

### Verification

- Debug build: passed.
- Release build: passed.
- Xcode Analyze: passed.
- Complete test suite: 164 passed, 0 failed, 0 skipped.
- Address Sanitizer suite: 164 passed, 0 failed, 0 skipped.
- Thread Sanitizer suite: 164 passed, 0 failed, 0 skipped.
- Current DerivedData build Time Profiler: 10-second bounded recording with no
  `potential-hangs` rows.

### Remaining release-validation risks

- The command-line Allocations instrument could not attach to the unsigned Debug
  process; Allocations, Leaks, Energy and Core Animation Hitches still require a
  signed interactive profiling session.
- Physical display hot-plug, mixed scaling, cloud-file drag/drop and visual
  Light/Dark/VoiceOver checks cannot be proven by the automated suite alone.
