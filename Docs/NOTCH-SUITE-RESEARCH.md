# Parcel notch-suite research

Research date: 14 November 2026. This is a product and implementation audit based on current public vendor documentation. It does not claim hands-on parity with paid competitors.

## Open-source reference audit

| Project | Licence | How Parcel used it |
| --- | --- | --- |
| QNotch | MIT | Reference for icon-only navigation, demand-loaded modules and explicit idle-performance budgets. |
| ILoveNotch | MIT | Reference for public notch geometry, a fixed top-attached surface and event-driven feature lifecycles. |
| Cyclop | MIT | Reference for an invisible-at-rest shelf and restrained native control density. |
| NotchDrop | MIT | Reference for the original notch shelf interaction and drag/drop affordance. |
| NotchIsland | MIT | Reference for collapsed live state, command-style actions and one shared card language. |
| Boring Notch / NotchApp | GPL-3.0 | Behaviour and visual research only. No source copied into proprietary Parcel. |

The redesign remains original Parcel code. It uses public AppKit and SwiftUI APIs plus Music and
Spotify's documented AppleScript dictionaries; it embeds neither private MediaRemote frameworks nor GPL code.

## What the market has converged on

The best notch utilities use three layers rather than presenting a wall of controls:

1. **Ambient strip** — now playing, a timer, meeting countdown, transfer progress, or one useful status.
2. **One compact expanded surface** — a reorderable tool rail with one active workspace.
3. **Contextual actions** — file and clipboard actions appear only for compatible content.

## Product structure implemented

- The notch dashboard is the default surface; Parcel is one widget and one tool inside it.
- A four-column packing layout supports `1×1`, `1×2`, `2×1`, `2×2`, and `4×4` widgets.
- Widgets are scrollable, directly rearrangeable, resizable and pinnable without opening Settings.
- Pinned widgets and pinned applications appear in the collapsed notch; applications launch only on click.
- Hover opens the dashboard and previews affordances, while drag/drop still routes files into Parcel.
- The resident panel is positioned against `NSScreen.frame`, not `visibleFrame`, so it occupies the menu-bar/notch region instead of floating below it.

This is visible across [NotchNook](https://lo.cafe/notchnook/), [Droppy](https://getdroppy.app/docs), [NotchDesk](https://notchdesk.com/), [OneNotch](https://www.tryonenotch.com/), [NotchStar](https://www.notchstar.com/), [QNotch](https://qnot.ch/mac/) and [Brow](https://brow-app.com/notch). NotchPixel is currently a Windows product, not a Mac reference implementation; its useful ideas are ambient game/system telemetry, universal microphone status, a file shelf and same-network phone handoff ([official site](https://notchpixel.com/)).

## Feature audit

| Capability | Strong references | Parcel response |
|---|---|---|
| File staging, transform, drag-out | Droppy, Dropover, NotchNook | Existing Parcel shelf, contextual conversion, packing, OCR and watched folders remain the primary module. |
| Clipboard search and type-aware actions | OneNotch, Droppy, NotchDesk | Existing local clipboard history is now a first-class notch module. |
| OCR / screen text | Droppy, Brow, OneNotch | Vision OCR for copied images, images and PDFs; results copy locally. Screen-region capture is a later permission-gated addition. |
| Colour picker | OneNotch, Brow, NotchDesk, QNotch | Native `NSColorSampler`; HEX is copied immediately. |
| Timer / live activity | NotchNook, NotchDesk, NotchStar, Brow | Persistent timer with an ambient collapsed-notch countdown, sound and local notification. |
| Notes | NotchNook, NotchDesk, NotchStar, QNotch | Local quick note with copy and optional Apple Intelligence summary. |
| QR | Brow / Windows notch tools | Local QR generation and Vision QR scanning. |
| Launcher and search | QNotch, Brow | Running-app launcher and explicit Google search. |
| Music | NotchNook, Droppy, NotchStar | Parcel controls Music and Spotify through their supported automation dictionaries and keeps a local audio-player fallback. It does not use private MediaRemote APIs. |
| Widgets / system glance | NotchPixel, Brow, NotchStar | Compact memory, CPU-core, uptime and recent-action cards. Live CPU/network graphs can follow. |
| Notifications | Droppy, NotchPixel | Parcel can emit its own actionable alerts and activity receipts. macOS does not expose a supported API for mirroring every other app's Notification Center. |
| On-device intelligence | NotchNook Pro, OneNotch | Foundation Models summary is availability-checked and stays on-device when Apple Intelligence is available. OCR remains the deterministic fallback. |

## Product rules

- Parcel is an accessory app. Launch starts the notch service; it does not open a normal app window.
- Settings, licence activation and onboarding remain real windows because they need durable keyboard focus and permission explanations.
- The old workbench is not a user-facing destination. Compatibility call sites summon the notch instead.
- Every module must work without a network except explicit Google search and future opt-in cloud handoff.
- No private media, notification or display APIs. Unsupported system-wide behavior is not simulated.
- The physical notch and menu bar remain the anchor. Expanded height is capped at 40% of the active display.
- Reduce Motion, Reduce Transparency, keyboard navigation and configurable shortcuts remain shared behavior rather than module-specific afterthoughts.

## Next depth milestones

The current implementation establishes the shared shell and eleven working modules. Release-level parity still requires: screen-region OCR and capture permission UX; calendar/meeting integration; reorderable and hideable modules; real system telemetry sampling; per-module global shortcuts; safe clipboard concealment rules; richer audio queue and metadata; multi-display visual acceptance; and a dedicated iPhone/iPad companion architecture. These should be added incrementally with permission and privacy review, not as one untestable feature dump.
