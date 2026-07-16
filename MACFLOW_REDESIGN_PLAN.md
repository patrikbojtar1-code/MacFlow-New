# MacFlow redesign plan

## Current architecture

MacFlow is a SwiftUI macOS application with AppKit window and panel management.

### App and window lifecycle

- `NotchLandApp.swift` creates the SwiftUI app and injects long-lived controllers.
- `AppDelegate.swift` starts module services and owns the shared runtime.
- `WindowManager.swift` owns the companion window, notch panel, status item, screen changes, onboarding presentation, and environment injection.
- `SettingsView.swift` is the compatibility root that currently renders `MacFlowHubView`.

### Current shell

- `MacFlowHubView.swift` currently contains the app shell, sidebar, top bar, Home, Notch wrapper, and Preferences wrapper in one file.
- `MacFlowDesignSystem.swift` provides an initial token layer but still mixes semantic design tokens with direct colors and page-specific measurements.
- `MacFlowLogo.swift` provides the shared mark and should remain the brand source.
- Navigation persists through `@AppStorage("macflow.selectedSection")`.

### Feature modules and view models

- Notch UI routes to existing `GeneralSettingsView`, `WidgetSettingsView`, `CalendarSettingsView`, `WalletSettingsView`, `BehaviorSettingsView`, and `AppearanceSettingsView`.
- Notch runtime is primarily driven by `NotchSettings`, `AppState`, and the controllers injected by `WindowManager`.
- MouseFree uses `MouseFreeController`, `MouseFreeScrollInterceptor`, and `MouseFreeScrollEngine`; `MouseFreeHubView` is presentation only.
- Wallpapers use `WallpaperSceneController`, `WallpaperSceneLibrary`, `WallpaperSceneAutomation`, `WallpaperPerformanceMonitor`, and runtime windows. `ScenesSettingsView` currently owns most wallpaper presentation and local UI state.
- Preferences reuse `GeneralSettingsView` and `AppearanceSettingsView`, which currently causes feature/app-level settings to overlap.
- About uses `AboutSettingsView` and `UpdaterController`.

## Baseline screen audit

### Home

Strengths:

- Clear three-module concept.
- Real runtime state is already available.
- Module navigation is direct.

Problems:

- Large marketing hero consumes too much vertical space.
- Cards repeat status already shown elsewhere.
- Global top status indicators and bottom runtime card are partly decorative.
- Information hierarchy does not clearly separate launch actions, runtime status, and module summaries.

### Notch

Strengths:

- Existing subsection model is correct.
- Underlying settings are functional and persistent.

Problems:

- Header and tab hierarchy feel detached from content.
- The page becomes a stack of generic setting rows.
- No meaningful overview of actual notch shape/runtime/capabilities.
- App-level settings such as launch behavior are mixed with feature configuration.

### MouseFree

Strengths:

- Real deterministic response model and permission state.
- Presets and tuning values are already separated from engine code.

Problems:

- Permission card is too visually dominant.
- Chart, presets, tuning, and behavior are four similarly weighted blocks.
- Preset cards are bulky.
- Numeric value alignment and graph labels can be more precise.

### Wallpapers

Strengths:

- Functional library, collections, favorites, import/export, automation, renderer profiles, and performance monitoring.
- Actual local preview URLs are available.

Problems:

- Current vertical dashboard buries the primary task: selecting and applying a scene.
- Runtime, performance, automation, collections, and library all compete as full-width cards.
- No persistent selection/inspector workflow.
- Search, kind filtering, sorting, and grid density are missing from the primary browser.

### Preferences

- Currently reuses feature-oriented General and Appearance pages.
- Needs a dedicated app-level information architecture and calmer grouped form.

### About

- Brand and updater work, but the screen is mostly empty.
- License, product scope, and credits are not structured.

## Reusable existing components and logic

Keep and reuse:

- All runtime controllers and persistence keys.
- `MacFlowLogoTile` and `MacFlowMark`.
- `MouseFreeScrollEngine` and event interception.
- Wallpaper library, package, automation, renderer, and performance logic.
- Existing settings bindings in `NotchSettings`.
- Native SwiftUI `Toggle`, `Slider`, `Picker`, `Menu`, `fileImporter`, alerts, and sheets.
- Existing scene preview URL generation and scene inspector editing bindings.
- Existing haptic and Reduce Motion infrastructure.

## Components to replace or refactor

- Split the monolithic `MacFlowHubView.swift` into shell, sidebar, Home, Notch, Preferences, and shared component files.
- Replace `MacFlowSurfaceModifier` with semantic panel styles.
- Replace repeated page-specific headers with `MacFlowPageHeader`.
- Replace independent settings cards with `MacFlowSettingsGroup` and `MacFlowSettingsRow`.
- Replace wallpaper dashboard composition with browser, active preview, grid tile, and selected-scene inspector components.
- Replace MouseFree preset cards with a compact selection strip and align the tuning grid.
- Replace the duplicated global top status cluster with contextual actions.

## Files to refactor

### Shared shell and system

- `NotchLand/MacFlowDesignSystem.swift`
- `NotchLand/MacFlowHubView.swift`
- new `NotchLand/MacFlowComponents.swift`
- new `NotchLand/MacFlowSidebarView.swift`
- `NotchLand/WindowManager.swift`

### Home and Notch

- new `NotchLand/MacFlowHomeView.swift`
- new `NotchLand/MacFlowNotchWorkspaceView.swift`
- `NotchLand/GeneralSettingsView.swift`
- optionally the existing Notch subsection views only where grouping requires it

### MouseFree

- `NotchLand/MouseFreeHubView.swift`
- no planned behavior rewrite in `MouseFreeController.swift`, `MouseFreeScrollEngine.swift`, or `MouseFreeScrollInterceptor.swift`

### Wallpapers

- `NotchLand/ScenesSettingsView.swift`
- new view-only wallpaper browser components as needed
- no planned storage/runtime rewrite in wallpaper controllers and models

### Preferences and About

- new `NotchLand/MacFlowPreferencesView.swift`
- `NotchLand/AboutSettingsView.swift`
- `NotchLand/SettingsView.swift` remains the compatibility root

### Tests

- existing `NotchLandTests/MacFlowIntegrationTests.swift`
- existing `NotchLandTests/WallpaperSceneTests.swift`
- add view-model/filtering tests where new presentation state contains nontrivial logic

## Rollout phases

### Phase 1 — system definition

- Audit screenshots, views, controllers, and persistence boundaries.
- Create `MACFLOW_REDESIGN_SYSTEM.md` and this plan.
- Commit documentation only.

### Phase 2 — shell and components

- Introduce semantic tokens and shared components.
- Split sidebar from page content.
- Introduce contextual page toolbar.
- Keep current pages mounted behind the new shell.
- Commit shell/component files.

### Phase 3 — Home, Notch, MouseFree

- Build command-center Home.
- Build Notch overview workspace and reusable subsection framing.
- Recompose MouseFree into tuning studio.
- Preserve all bindings and permissions.
- Commit the three modules and relevant tests.

### Phase 4 — Wallpapers

- Add browser presentation state: search, kind filter, sort, density, selected scene.
- Build active/selected preview, adaptive grid, and optional inspector.
- Retain import/export, favorites, collection actions, automations, renderer profile, and errors.
- Commit wallpaper presentation and tests.

### Phase 5 — Preferences and About

- Create dedicated app-level preferences.
- Redesign About into a compact product information page.
- Commit the two screens.

### Phase 6 — polish and verification

- Keyboard/accessibility labels and focus order.
- Reduce Motion, Reduce Transparency, and Increase Contrast behavior.
- Hover/pressed/disabled/loading/empty/error refinement.
- Build, test, visual screenshot comparison, Release build, and installed-app verification.
- Commit final polish.

## Risks and mitigations

### Dirty worktree and prior feature work

Risk: unrelated Notch and wallpaper changes are currently uncommitted.

Mitigation: stage explicit files for every phase; inspect `git diff --cached` before each commit; never use blanket `git add .`.

### Environment object coverage

Risk: splitting views may omit an environment object and cause runtime failure.

Mitigation: keep environment injection centralized in `WindowManager`; new child views consume existing objects without recreating them; compile previews only through the existing preview container.

### Wallpaper feature regression

Risk: browser redesign could hide import, automation, collection, profile, or package functions.

Mitigation: map every existing action before replacing `ScenesSettingsView`; keep controller API unchanged; cover filter/sort presentation state with tests.

### Accessibility permission churn

Risk: replacing local ad-hoc builds changes the TCC identity.

Mitigation: install only the final verified build; communicate that production requires a stable Developer ID signature; do not request Accessibility automatically.

### Layout at minimum window size

Risk: a persistent wallpaper inspector may crowd the library.

Mitigation: inspector width is bounded and collapses below the preferred browser width; library grid remains adaptive.

### Performance

Risk: live previews or thumbnails could trigger repeated decoding.

Mitigation: use existing preview URLs and `AsyncImage`; avoid processing inside `body`; render only visible grid cells through `LazyVGrid`; do not create video players for every tile.

## Rollback plan

- Every phase is an isolated git commit.
- Shell rollback keeps feature views and controllers untouched.
- Module rollback restores only that module's presentation files.
- Wallpaper runtime/storage remains independent of browser UI and can be retained even if the browser commit is reverted.
- No preferences keys, bundle identifier, scene package format, or storage locations are migrated during this redesign.

## Definition of done

- Home, Notch, MouseFree, Wallpapers, Preferences, and About use the shared system.
- Wallpapers is a selection/browser/inspector workflow rather than a dashboard.
- No runtime controller is duplicated or rewritten without a functional reason.
- Existing persistence and actions remain reachable.
- Full Debug test suite and Release build pass.
- Final screenshots are compared against the supplied Home, Notch, MouseFree, and Wallpapers baselines at the target window size.
