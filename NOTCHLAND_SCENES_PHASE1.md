# NotchLand Scenes — Phase 1

## Product boundary

Scenes is an isolated wallpaper subsystem inside NotchLand. Phase 1 does not
change the existing notch panel, media presentation, calls, onboarding, or
widget hierarchy. The current notch remains stable while the wallpaper runtime
is validated independently.

## Phase 1 goals

- Import local JPEG, PNG, HEIC, MOV, MP4, and M4V assets.
- Copy imported media into an app-owned scene library.
- Persist a versioned, Codable scene index.
- Render one selected scene across all connected displays.
- Support still-image and looping-video scenes.
- Pause video rendering without destroying the selected scene.
- Adapt playback to Low Power Mode and macOS thermal pressure.
- Restore rendering after display topology changes.
- Provide a native Scenes settings surface for import, selection, removal, and
  performance preferences.

## Non-goals

- Community accounts, uploads, ratings, or monetization.
- Executing downloaded JavaScript, shaders, plug-ins, or binaries.
- A public `.notchscene` package importer.
- A timeline or layer editor.
- Audio playback from wallpaper videos.
- Changes to the physical notch shape or its existing transitions.

## Architecture

### `WallpaperScene`

A small, Sendable, Codable manifest. It stores only app-owned relative file
names and never persists arbitrary executable URLs.

### `WallpaperSceneLibrary`

Owns the Application Support directory and the versioned `library.json` index.
Imports are validated, copied with generated names, and written atomically.
Deleting a scene also removes its copied asset.

### `WallpaperPerformanceMonitor`

Normalizes the user-selected Eco, Balanced, Cinematic, or Automatic profile.
Automatic mode responds to Low Power Mode and `ProcessInfo.thermalState`.

### `WallpaperSceneController`

Coordinates selection, pause state, performance policy, and one renderer window
per `NSScreen`. It observes display topology and power changes without involving
the main notch `WindowManager`.

### `WallpaperSceneWindow`

A transparent, non-interactive desktop-level window. Images use `NSImageView`;
videos use a muted `AVQueuePlayer`, `AVPlayerLooper`, and `AVPlayerLayer`.
Renderer windows never accept mouse input and join all Spaces.

## Storage

`~/Library/Application Support/NotchLand/Scenes/`

- `library.json` — versioned scene index
- `Assets/<UUID>.<extension>` — copied scene assets

The format deliberately excludes executable content. A future `.notchscene`
container will be introduced only after signing, budget validation, moderation,
and migration rules exist.

## Performance policy

| Profile | Target cadence | Automatic behavior |
| --- | ---: | --- |
| Eco | 24 | Always low-energy |
| Balanced | 30 | Default quality |
| Cinematic | 60 | User-requested maximum |
| Automatic | 24–60 | Responds to battery and thermal state |

At serious thermal pressure the runtime falls back to Eco and requests a 720p
decode ceiling. Balanced requests up to 1080p, while Cinematic preserves the
source resolution. At critical pressure video is paused until the system
recovers. Low Power Mode also selects Eco. Audio is disabled for every wallpaper
video.

## Files modified in Phase 1

- `NotchLand/AppDelegate.swift`
- `NotchLand/NotchLandApp.swift`
- `NotchLand/SettingsView.swift`
- `NotchLand/SettingsSidebar.swift`
- `NotchLand/WindowManager.swift`

## New files

- `NotchLand/WallpaperScene.swift`
- `NotchLand/WallpaperSceneLibrary.swift`
- `NotchLand/WallpaperPerformanceMonitor.swift`
- `NotchLand/WallpaperSceneController.swift`
- `NotchLand/WallpaperSceneWindow.swift`
- `NotchLand/ScenesSettingsView.swift`
- `NotchLandTests/WallpaperSceneTests.swift`

## Rollback

The feature is isolated behind the Scenes settings section. Removing controller
startup and its environment injection disables it without touching the notch.
The library remains user-owned data and is not deleted automatically.

## Phase 2 after validation

- Compact notch scene controller.
- Drag media onto a dedicated notch zone to create a scene.
- Scheduled collections and Focus-aware switching.
- Fullscreen-app suspension and per-display profiles.
- Scene thumbnail generation and transition previews.

## Phase 2 implementation scope

Phase 2 keeps the existing notch geometry and activity priority policy. Scene
controls appear only after calls, drop targets, critical alerts, live activities,
HUD, media playback, and calendar countdowns have had a chance to present.

- A single image or supported video dragged to the notch is routed to the Scenes
  importer instead of File Shelf.
- Other files and multi-item drags retain the existing File Shelf behavior.
- Video imports receive a cached local JPEG thumbnail generated once during
  import, never during SwiftUI body evaluation.
- The runtime pauses video when the login session is inactive, screens sleep, or
  the foreground application owns a true fullscreen window.
- Clicking the scene title wing opens Settings directly on Scenes; clicking the
  right control toggles playback.

## Phase 3 — collections, automation, and transitions

Phase 3 adds one shared scheduling model rather than separate background logic
for every Settings control.

- Every library owns a persistent, non-removable Favorites collection and any
  number of user-created collections.
- Smart Scenes can rotate Favorites at a 5, 15, 30, or 60 minute cadence.
- Morning, day, evening, and night can each select an explicit scene.
- A Focus-aware rule has highest automation priority when Focus is active.
- A manual selection or Stop action pauses automation for two hours; changing a
  Focus state does not unexpectedly replace the user's explicit choice.
- Scene changes build a second renderer per display and crossfade for 460 ms.
  The current renderer stays alive until the transition completes.
- Reduce Motion bypasses the crossfade and updates in place.

Automation configuration is persisted separately from the scene index. Scene
collections stay in `library.json`; deleting a scene removes its membership from
every collection atomically.

## Phase 4 — safe sharing foundation

The `.notchscene` package is a Finder package containing exactly:

- `manifest.json`
- one `asset.<supported extension>` image or video

Packages are data-only. Import rejects path traversal, nested assets, symlinks,
extra files, empty or oversized media, unsupported formats, future manifest
versions, oversized metadata, and SHA-256 mismatches. Hashing streams in 1 MB
chunks so large videos are not loaded into memory. The checksum establishes
asset integrity, not creator identity.

Scenes can be exported from the library, imported through Settings or notch
drop, and opened from Finder. A future public catalog still requires account
identity, server-side malware scanning, moderation, licensing declarations,
rate limits, abuse reporting, and a server signature before NotchLand can label
a creator as verified.

## Phase 5 — per-scene render engine profiles

Every scene now carries a versioned rendering profile. Existing version 1
manifests migrate to the default profile without changing their files.

- Scaling modes: Fill, Fit, and Stretch.
- Video playback rates: 0.5×, 0.75×, 1×, 1.25×, and 1.5×.
- Dimming: 0–70% black treatment applied above the rendered asset.
- Live Scene Inspector with a cached preview and automatic persistence.
- Active desktop windows receive profile changes without being recreated.
- Slider changes update the renderer immediately while library writes are
  debounced by 280 ms.
- `.notchscene` export and import preserve the normalized rendering profile.
- Reduce Motion removes the treatment animation while preserving the result.

The engine applies image scaling through `CALayer.contentsGravity`, video
scaling through `AVPlayerLayer.videoGravity`, and video speed directly through
`AVQueuePlayer`. The dimming layer stays above both renderer types and does not
require Core Image work on every frame.
