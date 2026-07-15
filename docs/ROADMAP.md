# NotchLand premium roadmap

This file tracks the production scope implemented for the NotchNook-like upgrade.
Every completed area is backed by source, automated tests where business logic is
involved, and the Release build installed at `/Applications/NotchLand.app`.

The next product generation is tracked in [ROADMAP_V2.md](ROADMAP_V2.md).

## Core notch experience

- [x] Notch-anchored panel across Spaces and full-screen apps
- [x] Hover/click/scroll interaction state machine
- [x] Shared spring motion tokens, matched geometry, blur, shadows, and haptics
- [x] Reduced Motion behavior and keyboard-accessible widget navigation
- [x] Persistent top module rail with drag ordering and Pinned, Automatic, and Hidden visibility modes
- [x] Event Center foundation with priority queue, interruption, deduplication, persistent Timeline and unread state
- [x] Personalized six-step onboarding with live feature fixtures, profile presets, interactive module setup, privacy education, Reduced Motion support, and replay from Settings

## Premium surfaces

- [x] Source-aware Apple Music, Spotify, and Apple TV designs with application identity, branded ambient themes, artwork morph, scrubber, and waveform
- [x] Calendar agenda, event details, and countdown chip
- [x] Persistent multi-file Shelf with drag-in/out, Quick Look, Finder, and AirDrop
- [x] Non-blocking folder-safe Shelf ingestion with off-main bookmark/metadata I/O and asynchronous restore
- [x] Persistent focus timer and compact live activity
- [x] Local Quick Notes
- [x] Persistent Tasks with favourites and automatic archive
- [x] Local Clipboard Shelf with pin, pause, deduplication, and clear controls
- [x] Customizable Quick Actions application launcher
- [x] Camera Mirror with permissions, lifecycle isolation, mirroring, and digital zoom
- [x] Provider-ready Call Experience with incoming, connecting, active, ended, and missed-call motion states
- [x] Multi-chain Exodus Wallet module with multiple public BTC, LTC, ETH, and SOL addresses, per-asset balances, contribution history, USD/EUR quotes, and physical-notch-safe compact/full payment presentations

## System integrations

- [x] Volume, display brightness, keyboard brightness, and contrast HUDs
- [x] Battery milestone and charging alerts
- [x] Focus mode alerts
- [x] Lock/unlock presentation
- [x] Audio device, timer, and download live-activity sources
- [x] Calendar, Accessibility, and Camera privacy flows
- [x] Safe call-provider callbacks and non-controlling fallback for third-party calling apps
- [x] Launch at login, update checks, replayable onboarding, and menu-bar controls

## Integration expansion

- [x] Bitcoin, Litecoin, Ethereum, and Solana native-asset providers for Wallet monitoring
- [ ] ERC-20, SPL, and other token transfer providers
- [ ] Exodus Checkout signed webhook provider
- [ ] Native Apple Reminders synchronization
- [ ] Creator Hub providers for Twitch, YouTube, Ko-fi, Stripe, and PayPal
- [ ] Extended meeting controls for Zoom, Google Meet, and Microsoft Teams
- [ ] Spotify Connect devices, queue, shuffle, and repeat
- [ ] GitHub workflow and pull-request activity
- [ ] Home Assistant scenes and device state
- [ ] User-defined context automation rules

## Production gates

- [x] MVVM-style controllers with dependency injection from `AppDelegate`
- [x] Local persistence for user-created shelf content
- [x] Automated controller and smoke tests
- [x] Clean arm64 Debug and Release builds
- [x] Release installed and ad-hoc signed in `/Applications`
- [x] Dock bookmark points to `com.rudrashah.NotchLand`
