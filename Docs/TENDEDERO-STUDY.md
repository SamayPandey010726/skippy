# Tendedero source study and Parcel direction

Study date: 15 October 2026. This records Step 1 only; implementation and runtime acceptance remain pending.

## Reference and scope

- Repository: https://github.com/alejandrobujan/tendedero
- Studied revision: `2c3ffd95f173585260aa198e85d3ea62a878f688` (13 October 2026).
- Local checkout: `/tmp/parcel-tendedero-study.sY8Qjg/tendedero`.
- Read all 17 native Swift files (2,988 lines), package configuration, licence, and relevant bundle configuration. Findings below describe the native implementation, not the interactive website demo.
- Paths and line numbers below refer to that revision under `Sources/Tendedero/`. They can be resolved at `https://github.com/alejandrobujan/tendedero/blob/2c3ffd95f173585260aa198e85d3ea62a878f688/`.
- Source is MIT; name, icon artwork, and documentation images have separate exclusions. Parcel should reuse interaction principles through its own implementation and art.

## What produces the physical feel

| Effect | Source | Exact mechanism |
| --- | --- | --- |
| Objects hanging from a line | `LineView.swift:32`, `PeggedView.swift:23` | Rope follows a parabola with sag `min(30, width * 0.018)`. Each card rotates about its top anchor; each item's resting tilt is randomly chosen in `-2.5...2.5` degrees (`Line.swift:15`). The clip overlaps the card by 12 points. |
| Arrival | `PeggedView.swift:125`, `LineView.swift:97` | Card begins 46 points above its destination with a 16-degree swing. Translation uses response `0.42`, damping fraction `0.72`; rotation settles with stiffness `46`, damping `2.6`. Line reveal uses response `0.42`, damping fraction `0.82`; item relayout uses `0.55` / `0.78`. |
| Hover and press | `PeggedView.swift:75`, `GrabArea.swift:104` | Hover grows the card to `1.035` and deepens/lifts its shadow. Holding compresses to `0.95` over `0.45s`, matching the long-press threshold. Release spring is response `0.3`, damping fraction `0.6`. A drag starts after 4 points of movement and cancels the hold. |
| Breeze | `Line.swift:304`, `PeggedView.swift:141` | Every random `7...16s`, a gust increments if items exist and no card is being dragged. Each card waits `0...0.35s`, nudges `1.6...3.4` degrees over `0.3s`, then settles with stiffness `38`, damping `2.4`. The timer does not explicitly gate on visibility. |
| Action feedback | `PeggedView.swift:137`, `Line.swift:156` | Landing nudges `2.2` degrees; copy nudges 3 degrees and shows a label for `1.2s`. The object responds to the completed action. |
| Capture flight | `CaptureFlight.swift:31`, `AppDelegate.swift:301` | `0.65s` cubic easing, 30-point sinusoidal arc, top-center anchor, progressively appearing glass and clip. Transient 120Hz timer drives layers with implicit animations disabled. At most two capture flights; thumbnail resolution capped at 1,500 pixels. Final overlap fades in `0.16s`. |
| Removal | `CaptureFlight.swift:83`, `Line.swift:107` | A separate full-display overlay avoids strip clipping: 520-point fall, cubic acceleration, extra rotation and fade over `0.55s`; logical item is hidden immediately and removed after `0.6s`. |
| Sound | `Line.swift:62`, `Line.swift:79`, `Line.swift:107`, `Line.swift:333` | System `Tink` at volume `0.35` on arrival and `Pop` at `0.25` on removal, plus the system trash sound. Sounds default on but can be disabled; batch removal sounds only once. Parcel's existing opt-in sound policy should remain. |

There is no particle system, mascot, scoring, or game engine in the native sources. The playful impression comes from a consistent object metaphor, reversible direct manipulation, small motion, and causal feedback. There is also no explicit Reduce Motion gate in these native sources; Parcel must retain and extend its own motion controls.

## System integration

`ScreenshotWatcher.swift:84` opens the screenshot folder with `O_EVTONLY` and creates a `DispatchSource` for write/rename/delete. Scans debounce by `0.2s` to allow temporary-file renames to finish. Directory opening, listing, sorting and metadata inspection happen off the main thread. The watcher is installed before the initial listing, and a missed-listing flag preserves events during scans. Existing files form the baseline; captures created after watcher initialization are still discovered if directory access was delayed.

`ScreenshotWatcher.screenshotFolder()` reads `com.apple.screencapture` preferences through `CFPreferences`, including macOS 27's `location-screenshot` key. On Desktop, the `com.apple.metadata:kMDItemIsScreenCapture` extended attribute identifies screenshots. Explicit extra folders accept images; only the owned inbox accepts recordings. `captureRect(of:)` in `CaptureFlight.swift:7` reads `kMDItemScreenCaptureGlobalRect` and converts its top-left coordinates to AppKit screen coordinates for the flight origin.

`Inbox.swift:61` optionally redirects screenshot/recording locations and file targets and disables the floating thumbnail, saving previous settings before changes. `restore()` restores them on quit, disable and handled termination signals. `AppDelegate.startWatcher()` keeps a tagged Desktop watcher as a safety net. These screenshot-specific behaviors do not belong in Parcel.

`LinePanel.swift:7` uses a transparent, borderless, nonactivating `NSPanel`: `.floating` level, `hidesOnDeactivate = false`, `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, `.fullScreenAuxiliary`, and explicit refusal to become key/main. It positions on the pointer's display. `AppDelegate.updateMousePassThrough()` converts screen to view coordinates and accepts mouse input only over card hit rectangles, expanded by 4 points. Hidden panels are ordered out after dismissal, preventing an invisible overlay from remaining above other apps.

`AppDelegate.swift:423` tracks the pointer at 30Hz in the common run-loop mode only while a line is wanted. Global and local mouse-click monitors suppress reveal when the user clicks a menu bar; there is no CGEvent tap. `HotKey.swift` uses Carbon registration. `main.swift` selects accessory activation policy, and the bundle sets `LSUIElement`. Deliberate editing/Quick Look actions activate the app, whereas ordinary line interaction preserves focus.

`FullScreen.swift` uses private `CGSMainConnectionID` / `CGSCopyManagedDisplaySpaces` to identify fullscreen Spaces, with separate-display UUID matching and a shared-Spaces fallback. Fullscreen reveal is off by default. Space/application notifications trigger immediate refresh and another after `0.8s`; display-configuration changes reposition the panel. This does not establish an always-on-top solution for Parcel. Parcel needs public AppKit behavior and native acceptance over fullscreen apps; it should not inherit private APIs or the fullscreen suppression default.

The optional clipboard watcher polls every `0.5s`, checks types and change counts, excludes private/transient copies, and decodes off-thread. This was studied to understand gating only: continuous clipboard capture remains explicitly cut from Parcel.

## Timing that protects the user's flow

`AppDelegate.swift:445` requires a `0.25s` menu-bar dwell; retract waits `0.5s` after leaving (`:478`). Incoming captures peek for `2.5s`. Manual reveal stays until visited and left. An active drag, press, context menu, pinned manual reveal or unexpired peek prevents dismissal. A menu-bar click suppresses reveal until the pointer leaves that band. Empty-line teardown waits `0.7s` and rechecks state. Delayed panel hiding rechecks visibility before ordering out.

The reusable pattern is asymmetric entry/exit with generous interaction grace: a spring entrance, quick predictable dismissal, no hiding during work, and no animation barrier before an action can succeed. Tendedero's idle breeze is unsuitable for Parcel's instruction that the courier wakes only when needed. Use short event-driven sway on summon, hover and successful drop instead.

## Parcel gaps found in the existing code

Baseline is branch `feature/shelf-share-licensing`, HEAD `3b08ebfc40d43a4ef099fb1a44740418a2c085ac`. Existing edits affect app icon assets and `Samples/A little place.png`; preserve them. Xcode 27.0 is installed.

- `Services/DragMonitor.swift` recognizes file URLs only. Its fallback polls every `0.25s`, needs cursor movement over 6 points, and does not track pasteboard generation. Browser image bytes and file promises need recognition; stale drag-board contents and own-drag suppression need explicit lifecycle handling. Permission assumptions in current comments must be verified during native testing.
- `Services/DropPopup.swift` is a fixed 232-point square at `.floating` level. It has no destination chooser and opens the workbench after file/text drops. Its SwiftUI `appeared` state is driven by view creation, so repeat panel summons need a controller-driven reveal lifecycle. Preserve its generation guard against stale fade completions.
- `Services/DockPicker.swift` partitions stored order into pinned-item parcels and the rest, caps at five, and does not explicitly sort by `updatedAt`. Its file-URL-only row drops open the workbench; the new row calls `newBox()`, which requests a rename sheet. Unify ranking as pinned-first then `updatedAt` descending, with four destinations in the primary popup. Keep Dock Spring Loading available.
- `Views/NativeBridges.swift` already receives local files, promises, images and text. Reuse/generalize that intake behavior for individual destinations. Bind one destination ID to an entire drop, including asynchronous callbacks; do not create a separate parcel per promised file. Preserve receiving accounting and disable or clearly handle busy states. Report success/failure inside the popup because hub-only alerts are insufficient.
- `ParcelApp.swift` installs services in the workbench's `onAppear`, and `WorkbenchView` supplies the hub opener. Background service installation must become independent of hub creation, while explicit Open Parcel must still work. Preserve the Dock entry point when choosing lifecycle/activation policy.
- Workbench breakpoints currently run on width changes, not initial layout; manual toggles can show columns at narrow widths. Search lives in the collapsible sidebar. General Preferences has a long non-scrolling stack inside a fixed 550-by-540 scene. These are code-review concerns to verify and fix in the UI pass. Skin coverage remains partial, including fixed illustration colors.

## Understood implementation and acceptance scope

1. Make the primary path a background drag shelf: supported external drag starts anywhere, a small courier/satchel appears on the relevant display, hovering reveals four ranked parcels plus New parcel, and dropping completes intake there. Offer the relevant finish/pick-up actions there so ordinary use does not require opening the hub. Packing remains a deliberate user action.
2. Use a nonactivating panel and appropriate public window-level/Space behavior, track displays and screen changes, and keep destinations stable under the pointer. Accept drops immediately even while art animates. Hold the panel through asynchronous reception, show completion/errors, then dismiss with a grace interval and cancellable generation checks. Determine precise motion/placement constants during implementation and native testing.
3. Retain Dock Spring Loading and hotkey invocation, background lifetime, persistence, original-file safety, three skins with identical behavior, quiet opt-in sound, and instant transitions under Reduce Motion. Verify Reduce Transparency and High Contrast treatment. Preserve the living-shelf direction and $9.99 one-time positioning. Do not add cut features or change auto-clear/cache-cleanup behavior.
4. Audit every hub surface and state: initial/narrow/wide layout, sidebar, item list, inspector, search/keyboard flow, Preferences, all skins and persistence, menus, empty states, preparation and Pack. Native testing must cover Finder/Desktop/browser drags, multi-file and promise/image intake, existing/new destinations, cancellation, repeat summons, busy/error cases, focus preservation, Spaces and fullscreen. Exercise additional physical displays if available; explicitly record anything unavailable.
5. After implementation, run `swift test`, `bash Scripts/check-macos.sh`, `bash Scripts/build-macos.sh`, and native UI checks; self-review and fix findings, update verification/manifest as appropriate, then use the brief's explicit authorization to commit and merge the feature branch into `main` once checks pass. Leave the built app running with reproducible test commands. Do not claim runtime results or request user testing before doing the Mac verification.

This study confirms the task and its constraints before application changes or builds begin. Actual macOS system-owned surfaces can impose limits on window ordering; fullscreen and multi-display behavior require observed evidence rather than a claim based solely on flags.
