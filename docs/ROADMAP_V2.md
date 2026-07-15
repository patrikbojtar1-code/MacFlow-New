# NotchLand V2 — Intelligent Mac Layer

This roadmap evolves NotchLand from a set of notch widgets into a contextual,
extensible event surface for macOS. Work is ordered by architectural dependency,
not only by visual impact. Every milestone requires a clean Debug and Release build,
automated business-logic tests, Reduced Motion behavior, VoiceOver labels, and no
collection of private user content without explicit opt-in.

## Product principles

- The physical notch remains the visual anchor, never an obstruction.
- The most relevant moment wins; less important moments wait instead of disappearing.
- Local-first and read-only integrations are the default.
- Motion communicates state and causality rather than decorating the interface.
- Every automatic behavior is explainable, previewable, and reversible.
- New providers plug into stable protocols instead of adding branches to the root view.

## Milestone 1 — Event foundation

Status: in progress

- [x] Normalized `NotchEvent` model with source, correlation ID, priority and progress
- [x] Central event center with interruption and ordered pending queue
- [x] Correlation-based updates without duplicate history records
- [x] Persistent local history with retention limit and unread state
- [x] Bridges for Wallet, Calls, Battery, Focus and Live Activities
- [x] Timeline widget with source identity, progress, relative time and clear action
- [x] Drive Wallet, Calls, Battery, Focus and Live Activity presentation from Event Center authority
- [ ] Configurable per-source priority and history retention
- [ ] Quiet delivery policy for screen sharing, Focus and presentation mode
- [ ] Event actions: open source app, pin, retry and copy
- [x] Dismiss/skip action with automatic queue promotion
- [ ] Group repeated events into expandable stacks

Definition of Done: adding a new source requires a provider and renderer, with no edit
to the root priority switch.

## Milestone 1.5 — Shortcuts Bridge reference integration

- [x] Protocol-driven Apple Shortcuts discovery and execution
- [x] Direct Process arguments without shell interpolation
- [x] Async loading, running, success and failure states
- [x] Persistent favorite Shortcuts and favorites-first ordering
- [x] Dedicated Shortcuts top-rail module
- [x] Running and result events bridged into Event Center and Timeline
- [x] Pass File Shelf files and folders as typed Shortcut input paths
- [ ] Pass selected text, URL and clipboard content as typed input
- [ ] Capture structured Shortcut output for downstream Flow actions
- [ ] App Intent actions for controlling NotchLand from Shortcuts
- [ ] Per-shortcut custom symbol, color and confirmation policy
- [ ] Background execution queue with cancellation and timeout

Definition of Done: Shortcuts work bidirectionally—NotchLand can execute them with typed
input and Shortcuts can publish events or change NotchLand state through App Intents.

## Milestone 2 — Dynamic presentation orchestrator

- [ ] Presentation contracts for compact, banner, expanded and persistent surfaces
- [x] Priority preemption policy with graceful interruption
- [x] Return transition to the previously interrupted event
- [ ] Shared-element morph between event chip, Timeline row and expanded detail
- [ ] Event-specific duration policy with user overrides
- [x] Expanded-interaction policy that defers ambient Wallet and Live Activity surfaces
- [ ] Coalescing window for bursts such as multiple downloads or donations
- [ ] Full-screen and screen-sharing safe presentation modes
- [ ] Presentation diagnostics overlay for priority and queue inspection

Definition of Done: simultaneous call, payment, download and HUD events always render in
deterministic order without flicker, content loss or overlapping animations.

## Milestone 3 — Motion Engine V2

- [x] Central measured semantic motion graph: hover, enter, interrupt, success, expand, return and dismiss
- [x] Shared section choreography with compression, one-frame identity handoff and delayed content entry
- [x] Separate ambient-motion cadence and Reduced Motion cancellation policy
- [ ] Velocity-aware hover and drag transitions
- [ ] Interactive drag-to-expand with rubber-band resistance
- [x] Intent Hover delay that distinguishes a pass-through from a deliberate notch interaction
- [x] Physical-notch-safe left Timeline, center default and right Shortcuts zones
- [x] Immediate cancellation for drag, alerts, expansion and pointer exit
- [ ] Horizontal Timeline gesture and vertical detail gesture
- [ ] Ambient gradients extracted from media artwork and source application identity
- [ ] Lightweight particles for successful payments, transfers and completed tasks
- [x] Shape interpolation between bare notch, compact chip and expanded panel
- [ ] Low Power Mode animation budget
- [ ] Stable 60/120 Hz instrumentation and dropped-frame diagnostics
- [x] Complete Reduced Motion equivalents without hidden functionality
- [x] Secure-screen lifecycle reattach across lock, sleep, wake and unlock

Definition of Done: every transition preserves visual identity and remains responsive while
five event sources update concurrently.

## Milestone 4 — Context Engine

- [ ] Observe frontmost application through a privacy-safe local source
- [ ] Built-in Work, Meeting, Creator, Media, Gaming and Minimal contexts
- [ ] Rules combining app, time, Focus, display, audio device and power state
- [ ] Automatic widget pinning without overwriting manual configuration
- [ ] Explain-why UI for every automatic decision
- [ ] Rule priority, conflict resolution and cooldown
- [ ] Context preview and simulation
- [ ] Export and import rule sets
- [ ] Shortcuts actions to activate profiles through App Intents
- [ ] On-device suggestions based only on local aggregate behavior

Definition of Done: opening Xcode, a meeting app or a media player activates the expected
profile predictably, and the user can see and override the exact rule responsible.

## Milestone 5 — Wallet and Creator Hub

- [ ] Token registry for ERC-20 and SPL assets
- [ ] Custom token contracts with metadata validation
- [ ] Multiple wallet profiles and address groups
- [ ] QR receive cards and shareable payment requests
- [ ] Confirmation-depth progress and pending-to-confirmed morph
- [ ] Fiat goals with daily, weekly and campaign progress
- [ ] Privacy mode with hidden or rounded amounts
- [x] LocalAuthentication Privacy Shield for sensitive widgets with automatic relock
- [x] Local Face Unlock Beta with authenticated enrollment, device-only templates, liveness and lockout
- [x] Siri/App Intents for modules, timer, notes and Privacy Shield lock
- [ ] Ko-fi, Stripe and PayPal provider adapters
- [ ] Twitch follow, subscription and donation adapter
- [ ] YouTube Super Chat and membership adapter
- [ ] OBS-safe local overlay endpoint
- [ ] Alert themes based on amount tiers
- [ ] Donation message moderation and safe text rendering
- [ ] CSV export of contribution history

Definition of Done: creators can combine crypto and fiat contributions into one local-first
timeline and presentation system without giving NotchLand custody of funds.

## Milestone 6 — Meetings and communication

- [x] FaceTime and iPhone Continuity system-banner source with privacy-limited Accessibility scanning
- [ ] Provider protocol for Zoom, Teams, Meet, Slack and Discord
- [ ] Incoming, connecting, active, ended and missed event normalization
- [ ] Microphone and camera status with clear privacy indicators
- [ ] Meeting duration and next-event handoff
- [ ] Safe controls only where a provider explicitly supports them
- [ ] One-click note creation linked to the calendar event
- [ ] Clipboard-aware meeting link detection
- [ ] Configurable meeting Focus activation
- [ ] Post-call summary card with duration and notes

Definition of Done: unsupported applications remain display-only and never simulate controls
that cannot be executed reliably.

## Milestone 7 — Productivity integrations

- [ ] Native Apple Reminders synchronization
- [ ] GitHub pull requests, reviews, Actions and releases
- [ ] GitLab merge requests and pipelines
- [ ] Linear issue assignments and state changes
- [ ] Jira issue and sprint events
- [ ] Notion recent pages and quick capture
- [ ] Xcode build, test and archive activity provider
- [ ] Docker container health provider
- [ ] Figma export completion provider
- [ ] Download providers with pause, retry and reveal actions
- [x] Folder-safe File Shelf ingestion with no filesystem work in the AppKit drop callback
- [x] Drop Intelligence classification for folders, images, PDF, media, archives, code and batch drops
- [x] Contextual Preview, AirDrop, Reveal, Copy Path and prepared Shortcuts actions

Definition of Done: providers use async/await, expose explicit authorization state, degrade
offline, and never block the main actor with network or filesystem work.

## Milestone 8 — Home and device awareness

- [ ] AirPods and Bluetooth device battery timeline
- [ ] Audio output switching with explicit confirmation
- [ ] External display layout and notch-free presentation mode
- [ ] Home Assistant entity, scene and automation provider
- [ ] Network/VPN state events
- [ ] Apple device continuity status where public APIs permit it
- [ ] Charging time and battery health insights
- [ ] OLED/static-content protection policy

Definition of Done: hardware features remain optional and report unsupported capabilities
honestly on every Mac model.

## Milestone 9 — Visual editor and personalization

- [ ] Live virtual MacBook/notch canvas in Settings
- [ ] Compact and expanded layout editor
- [ ] Per-event theme, duration, sound and motion controls
- [ ] Design presets with import/export
- [ ] Accessibility contrast preview
- [ ] External-display layout presets
- [ ] Custom action and widget icons
- [ ] Safe reset with visual diff before applying
- [ ] iCloud sync for non-sensitive preferences

Definition of Done: all customization is token-driven, previewed before commit, and remains
legible in Light, Dark, Increased Contrast and Reduced Transparency modes.

## Milestone 10 — Plugin SDK

- [ ] Versioned provider and renderer protocols
- [ ] JSON/WebSocket local event API
- [ ] Signed local webhook endpoint with replay protection
- [ ] Sandboxed permission declarations
- [ ] Plugin lifecycle, health and crash isolation
- [ ] Developer preview and event simulator
- [ ] Templates for event-only, widget and action plugins
- [ ] Compatibility validation and API migration guide
- [ ] Curated plugin gallery metadata
- [ ] Per-plugin data and network visibility controls

Definition of Done: a third-party integration can be developed, previewed and disabled
without modifying or destabilizing the NotchLand application target.

## Milestone 11 — Reliability, privacy and release quality

- [ ] Snapshot tests for every compact and expanded state
- [ ] Event-storm, queue and persistence stress tests
- [ ] Performance signposts for rendering and provider latency
- [ ] Memory-pressure and sleep/wake recovery tests
- [ ] Permission revocation handling while running
- [ ] Corrupt-persistence recovery and schema migrations
- [ ] Optional privacy-preserving crash reports
- [ ] In-app diagnostics export with automatic secret redaction
- [ ] Signed and notarized release pipeline
- [ ] Staged update channels and rollback support
- [ ] Localization architecture and Czech/English launch languages

Definition of Done: release candidates pass automated functional, visual, performance,
accessibility and migration gates before installation.

## Recommended delivery sequence

1. Finish Event Center and make it the only compact presentation authority.
2. Build Dynamic Orchestrator and Motion Engine together.
3. Add Context Engine with explainable automation.
4. Deliver Wallet/Creator Hub as the flagship differentiated experience.
5. Add Meetings, Reminders, GitHub and Xcode providers.
6. Ship the visual editor after event contracts and tokens are stable.
7. Open the Plugin SDK only after first-party providers validate the API.

## Success metrics

- Zero lost high-priority events during simultaneous updates.
- Under 16 ms render time for ordinary transitions on supported hardware.
- Under 100 ms perceived response for local interactions.
- No private keys, seed phrases or wallet credentials accepted by the app.
- Every automatic context change exposes a reason and one-click override.
- Every source can be muted, hidden from history and disconnected independently.
