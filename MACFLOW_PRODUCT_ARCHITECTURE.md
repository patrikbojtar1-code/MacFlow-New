# MacFlow product architecture

## Product direction

`MacFlow` is the user-facing product shell for three integrated Mac experiences:

1. **Notch** — contextual activities, widgets, media, calls, files, calendar, and system feedback.
2. **MouseFree** — refresh-rate-independent smooth scrolling for external mechanical mice.
3. **Wallpaper Engine** — a local scene library, live wallpaper renderer, schedules, collections, and shareable `.notchscene` packages.

The app remains one process, one settings window, one menu-bar item, and one persistent preferences domain. The existing bundle identifier and update channel are intentionally retained during this migration so installed users do not lose permissions, preferences, or updater continuity.

## Unified information architecture

The main window is the MacFlow Hub and contains:

- **Home** — health and status of all modules, quick navigation, and continuity overview.
- **Notch** — existing notch configuration grouped into General, Widgets, Calendar, Wallet, Behavior, and Appearance.
- **MouseFree** — engine status, Accessibility permission, response presets, speed, smoothness, acceleration, reverse scrolling, and Option bypass.
- **Wallpaper Engine** — scene library, import, playback, collections, inspector, automations, and performance state.
- **Preferences** — shared launch, appearance, and app-wide behavior.
- **About MacFlow** — product identity and version.

The sidebar is the single top-level navigation surface. Individual modules may have local tabs, but they must not open separate settings applications.

## Shared UI system

The shell uses shared tokens in `MacFlowDesignSystem.swift`:

- `MacFlowSection` defines navigation identity and module accent.
- `MacFlowMetrics` defines window, sidebar, card, padding, and spacing values.
- `MacFlowTheme` defines surfaces, strokes, and secondary text.
- `MacFlowMotion` defines Reduce Motion-aware selection and content transitions.

Module accents identify context without recoloring an entire page. Cards use native macOS surfaces and restrained strokes. Navigation transitions preserve the window geometry and replace only the detail content.

## Runtime ownership

`AppDelegate` owns the long-lived module controllers:

- `NotchSettings` and the existing notch runtime.
- `MouseFreeController` and its event interceptor.
- `WallpaperSceneController` and wallpaper windows.

The controllers are injected into the MacFlow Hub as environment objects by `WindowManager` and `NotchLandApp`. Views present state and user intent; they do not own global engines.

## MouseFree integration

The standalone MouseFree project was used as a source for the scrolling behavior only. Its duplicate notch, widget, and app-shell code was not migrated.

The integrated module is separated into:

- `MouseFreeScrollEngine` — deterministic, testable momentum physics.
- `MouseFreeScrollInterceptor` — CGEventTap input and display-synchronized output.
- `MouseFreeController` — persistence, Accessibility trust, lifecycle, and presets.
- `MouseFreeHubView` — MacFlow-native presentation.

Continuous trackpad and Magic Mouse events stay native. MacFlow transforms only discrete mechanical wheel events, supports an Option-key bypass, and stops interception when disabled or untrusted.

## Wallpaper Engine integration

Wallpaper scenes remain local-first. The library supports image and video scenes, collections, favorites, renderer profiles, focus/time automation, and `.notchscene` import/export. Wallpaper windows are runtime surfaces controlled from the Hub; they are not separate apps.

Future community upload and discovery should be added as a service behind the existing scene library rather than replacing it. Downloaded scenes must pass package validation before appearing in the local library.

## Permission strategy

Permissions are requested only by the feature that needs them:

- MouseFree requests Accessibility only after the user enables the module or presses the permission action.
- The controller re-checks trust whenever MacFlow becomes active after a visit to System Settings.
- Wallpaper file access uses user-selected URLs and security-scoped bookmarks.
- Notch integrations retain their existing narrow permissions.

MacFlow must never repeatedly prompt when the corresponding macOS trust state is already granted.

## Naming and compatibility migration

This phase changes user-facing copy to MacFlow but intentionally does not yet rename the Xcode project, executable, bundle identifier, preferences keys, or updater feed. A later signed migration may rename the binary after verifying:

1. Accessibility permission continuity.
2. Login item migration.
3. Sparkle/update channel continuity.
4. Existing wallpaper security-scoped bookmarks.
5. Existing NotchLand and MouseFree preferences.

Until that migration is verified, changing these identifiers would make one integrated app feel like a fresh unrelated install and could trigger unnecessary permission prompts.

## Next product phases

1. **Shared command palette** — search settings, launch shortcuts, activate a scene, and toggle modules from one keyboard surface.
2. **Flows** — user-created triggers and actions connecting Notch, MouseFree profiles, wallpaper scenes, Focus, calendar, and Shortcuts.
3. **Community scenes** — account-optional browsing, signed packages, moderation metadata, local preview, and explicit install.
4. **Unified onboarding** — choose modules, explain permissions in context, import existing MouseFree preferences, and select the first wallpaper collection.
5. **Menu-bar quick controls** — one compact menu for module status and frequent actions without duplicating the full Hub.

## Verification baseline

- Debug build and the complete macOS test suite must pass.
- Release must build with signing disabled in CI/local verification.
- MouseFree physics is tested across 60 Hz and 120 Hz time steps.
- Denied Accessibility trust must never start the event interceptor.
- Module settings and the selected Hub section persist across relaunches.
