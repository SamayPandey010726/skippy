# Courier shelf implementation — 15 October 2026

The current user-requested redesign is documented in [Side courier](SIDE-COURIER.md). It supersedes the bottom-opening layout, multiple parcel pins, automatic Dock hub reopen and separate Dock picker described in earlier historical entries below. Current verification is 30 core + 34 app tests (64 total), native image/archive smoke and signed bundle validation. Real video export and native watched-folder intake pass. The menu-bar click-to-restore live gate remains pending user confirmation; no conditional commit/merge has been performed.

## Implemented

- External drag detection recognizes file URLs, images, URLs and file promises from pasteboard types without loading their contents. Mouse events start a 30Hz fallback only while the button is held; there is no idle polling. It rejects stale drag pasteboards and clears own-drag suppression on mouse release.
- A nonactivating, non-key/non-main panel uses the public popup-menu window level and joins Spaces/fullscreen auxiliary windows. It follows the pointer onto another display during a drag and reacts to display/Space changes. Actual fullscreen and physical multi-display behavior still require live acceptance.
- The courier is permanently visible by default, with an opt-out in Preferences. Hover expands four destinations, ranked pinned-first and then by modification date, plus New parcel. Ranking is frozen during an external drag. Expansion reserves screen space and preserves the avatar's top-right anchor. The grip persists its parked position.
- Every intake operation captures one destination ID, including every promised-file callback. Drops update the shelf without opening the hub or requesting a rename. Reception, errors, packing, saving, sharing and individual/packed drag-out are available in the shelf. Promise failures remain visible if another file in the same operation succeeds.
- The hub is created only on explicit request. Onboarding waits for that request rather than opening a startup window. Services start independently of its view. Dock Spring Loading remains available and uses the same intake path and ranking policy. Explicit Dock reopen brings the hub back; file-open events initialize services before handling incoming files.
- Original satchel artwork responds to summon, hover and successful intake with anchored spring motion. Bags unfold and open above stationary drop targets. There is no decorative idle loop. All three skins share geometry and behavior; motion respects Reduce Motion. Shelf and hub surfaces use native glass material, with opaque Reduce Transparency fallback and stronger High Contrast borders.
- Hub colors follow the skin palette, search remains reachable with collapsed columns, compact windows have sidebar/inspector popovers, Preferences scrolls, and inspector controls fit their column. Item-list arrow navigation and Space for Quick Look are present. Press feedback responds quickly.
- Native smoke checks use isolated temporary storage. Build scripts support both SwiftPM object layouts and opt-in settings for restricted build environments. If native icon conversion is unavailable, an ICNS container is assembled from the existing PNG representations without changing asset pixels.

The Tendedero study and the reasoning behind these choices are in `Docs/TENDEDERO-STUDY.md`. The later comparison and interaction plan are in `Docs/DROPOVER-RESEARCH.md`. No private fullscreen APIs or cut product features were introduced. Existing auto-clear/cache age rules are unchanged; new Bin parcels are included in retained references so existing cleanup cannot invalidate a recoverable entry. Existing user edits to icons and the sample image are preserved.

## Evidence and remaining acceptance

| Check | Result |
| --- | --- |
| Swift tests with layout export enabled | 54 passed, no skips or failures, under Full Access |
| Core packaging/name/persistence/drag-state/ranking/geometry/Bin tests | 28 passed |
| App controller/intake/Bin and review-render tests | 26 passed, including native-move event routing, hover timing, explicit activation, batch publication, pasteboard type recognition and file-URL copy |
| Python licence-tool tests | 4 passed using the bundled Python runtime with `cryptography` |
| Native release bundle | Built with Xcode 27.0; ad-hoc signature and plist validation passed |
| ICNS fallback | All 10 image representations decoded independently with Pillow |
| Offscreen native view review | Rendered and inspected narrow/wide and minimum-size hub, empty states, all Preferences tabs, welcome/rename/prepare, shelf chooser/contents/reception/packing/ready/error, and three courier art variants; these are view renders, not evidence of live cross-app drags |
| Native image smoke | Passed under Full Access: resize, opaque PNG→JPEG, GPS removal, transparency guard, PNG export, cancellation and native licence signatures |
| Launch Services | Rebuilt bundle launches through Computer Use with only the compact courier visible; no automatic hub |
| Live UI automation | Access now works. Exercised shelf creation, explicit hub entry, native file-picker intake of a disposable text fixture, Copy feedback, Quick Look without hub, pinning, both Bin confirmations, Restore and cancelling Empty Bin. Cross-app drags, actual pointer-hover timing, fullscreen/Spaces, physical displays and OS-accessibility toggles remain unverified |
| Git completion | Local `.git` writes verified with an isolated temporary probe; `gh` authenticates as SamayPandey010726 and reads the repository. No commit or merge because the user explicitly conditioned both on all required checks passing and live UI acceptance is incomplete |

## Follow-up verification

### Native courier movement — current result

The user reported that moving the icon was still laggy. The previous grip used a local SwiftUI DragGesture while moving the window containing that coordinate space, then recalculated display constraints and called setFrame(display: true) on every drag update. Replaced that path with NSWindow.performDrag(with:) using the original mouse-down event. The installed AppKit NSWindow.h documents this as a Window Server drag which returns immediately and may consume mouse-up. A temporary 50ms release check therefore ends movement and saves the final top-right anchor once; it does not update movement or run while idle. No screen lookup, SwiftUI translation, animated frame change or full-panel redraw is requested for each movement event.

Both the grip and avatar support native movement. The avatar preserves ordinary click-to-toggle behavior and distinguishes a movement threshold from file drag-out. Incoming file drops still go through their existing receiver. A press pauses hover expansion before it can change the window under the pointer. Pending hover/previews and hide work are cancelled; resizing waits until release. If the content changes during a move, its layout is applied once afterwards. The courier does not immediately unfold again when released beneath the pointer.

New tests verify original mouse-down forwarding, one movement handoff despite repeated drag events, click-versus-drag behavior, and hover/collapse suppression through movement. Full result: 28 core + 26 app tests, zero failures/skips, with updated view exports; release build/signature/plist pass. The rebuilt app was launched through Computer Use with the new draggable-avatar help text. Movement actions were attempted, but changing hover state and an intermittent stale-app guard made the automated pointer check inconclusive; no frame-rate or subjective smoothness claim is made. Cross-app and physical-display acceptance remains incomplete, so the conditional commit/merge gate is unchanged.

### Compactness and responsiveness — earlier result

Reviewed twelve frames spanning the user's 79-second recording and the supplied size reference. The previous shelf allocated 420×612 points even for an empty chooser, retained long-lived receipts, and used two always-running polling loops. The courier is now 64×68, the chooser 320×216, and file contents start at 320×312, capped by three visible rows plus optional archive/status controls. All files remain accessible by scrolling. A same-anchor 180ms native window transition clips a fixed, top-right-aligned content canvas rather than squeezing its controls during resizing. Hover intent is 80ms, exit grace 450ms, bag preview dwell 160ms. Re-entry cancels collapse; explicit summons allow time to reach the panel. Reception, packing and outgoing drags remain protected from dismissal.

Removed the decorative marketing header, large empty-state block, per-row instructional subtitles, redundant counts, idle pointer timer and blurred satchel shadow. The new tracking area works while inactive and during drags. Drag monitoring is event-driven with a temporary button-held fallback, not a permanent idle timer. Satchels do not animate on initial creation; action swing is smaller. Batch ingestion builds one updated parcel and publishes once rather than repeatedly invalidating the shelf and its ranking for every added file. A 24-file duplicate-input test verifies one library publication and one celebration per batch. Existing original-file and retention rules are unchanged.

The hub no longer opens for first-run welcome or incidental activation. Reopen handling requires an actual post-launch reopen Apple event; explicit hub controls remain available. Its new initial size is 900×640 with a new frame-autosave key, avoiding automatic restoration of the old oversized layout. Standard titlebar geometry replaces full-size content under the titlebar; native chrome follows skin appearance. Header/hero spacing is reduced. A separate noninteractive search placeholder avoids AppKit's dimmed native prompt on a custom dark background.

Automated pass: 28 core + 24 app cases, zero skipped or failed; native image/archive smoke and release signing/plist pass. Layout exports are in `.build/compact-previews/`, including a 24-item, long-filename packed shelf. Existing compiler and OS-service diagnostic warnings are not treated as a warning-free build.

Computer Use now connects successfully. Live-tested resident-only launch, compact chooser and contents, creating a parcel without the hub, explicit All parcels opening, a native picker with `/tmp/Parcel-compact-QA/parcel-hover-check.txt`, per-file Copy success feedback, Quick Look showing that file while the hub stays closed, pin preservation through Bin restore, shelf and hub delete confirmations, and Empty Bin confirmation followed by Cancel. The native capture service intermittently returned -3811 around the file picker; a subsequent AX observation recovered, and the controlled fixture was imported successfully. The one test parcel was left recoverable in Bin; no originals or Bin entries were permanently deleted. The test file and clipboard copy contain only the disposable QA text.

The final bundle was restarted again and verified to show only its resident courier. The capture service also returned -3811 when inspecting the final hub after the native-chrome/default-size adjustment; that last hub pass is covered by the updated offscreen renders, not a successful final live screenshot. The hub was closed with Command-W, and the final app remains running with only its courier visible.

Still not claiming complete acceptance: actual pointer hover/motion smoothness and cross-app drag/promise/Spaces/multiple-display/OS-accessibility behavior require further live verification. No commit or merge while the user's all-checks condition is incomplete. Earlier permission failures below are historical, not the current access state.

### Full Access recheck — earlier result

The user selected Full Access and requested a fresh test pass, with commit and merge only if all checks pass. Local Git metadata is now writable, verified by creating/removing only a uniquely named probe file. GitHub CLI authentication succeeds through the keyring as SamayPandey010726; the earlier invalid-token output was produced in the restricted environment and does not require a new login.

The normal commands now pass without sandbox/debug-info overrides:

```sh
PARCEL_PREVIEW_DIRECTORY="$PWD/.build/full-access-previews" swift test
bash Scripts/check-macos.sh
bash Scripts/build-macos.sh
```

Results: 27 core + 21 app cases = 48 passed, zero skipped, zero failed. All four Python licence-tool cases pass. Native smoke now passes coordinated image resize, JPEG/PNG export, GPS metadata removal, transparency rejection, cancellation and native signature validation; the generated archive also passes `unzip -t`. The release bundle's ad-hoc signature and plist validate. Current offscreen exports are in `.build/full-access-previews/`. These remain component renders, not live UI evidence.

Findings repaired during this pass: macOS Bash 3 treats an empty array expansion under `set -u` as unbound; both build/check scripts now omit empty option arrays safely, verified with empty and space-containing populated arguments and by running the real scripts with default settings. Bin restore now refuses a duplicate active parcel identity without discarding the recoverable Bin entry. The search prompt has an explicit skin-appropriate color rather than relying on native placeholder appearance against a custom background. New tests cover the restore collision and native file-URL clipboard copying, including preserving an existing isolated clipboard when one source is missing. No user clipboard or library was used for those fixtures.

Computer Use still refuses Parcel-specific access after the permission update and after a connection reset. Full Access fixes shell/filesystem/keyring access, not the separate app-control approval. The approval prompt's visibility was asked about while checks ran. No alternate UI automation or permission modification was attempted. Per the user's conditional approval, changes remain uncommitted and unmerged until the remaining live acceptance gates pass. Git access is no longer a blocker.

### Permanent courier and Bin update — earlier restricted pass

The user's later request explicitly authorizes a permanent avatar. The courier now remains as a small, quiet satchel rather than disappearing. Hovering without a drag unfolds the same bags. A cancellable 160ms preview dwell opens a bag without moving its drop target; leaving a bag keeps its contents available. Re-hovering the same selected bag preserves a just-built archive, while an explicit hub reopen still invalidates possibly stale archives. Manual collapse waits for pointer exit before allowing another hover expansion, preventing an immediate reopen loop.

Each bag has a direct parcel pin and Bin icon. An optional explicit pin flag is backward-compatible with libraries whose ranking came from piece pins; an explicit unpin overrides that legacy ranking without unpinning the pieces. The hub and menu use the same pinned/recent ordering. Preview lists scroll through every piece. File rows accept additional drops, open on click, drag out with copy semantics and expose Copy and Quick Look. Copy all validates every source before changing the clipboard. Paste, Pack, archive Copy/Save/Share, All parcels and Bin remain accessible without automatic hub activation. Explicit hub/Bin navigation collapses the shelf.

Bin moves are confirmed inline in the shelf and via confirmation in the hub. The Bin has Restore, confirmed individual permanent removal and confirmed Empty Bin. A whole parcel, its pin, note, items and deletion date persist. Entries expire after 30 days, checked on startup and by a deadline timer, deferred during packing/reception. A late restore cannot recover an expired entry. Saving a Bin transaction failure rolls back its in-memory change. Cached copies and bookmark access remain referenced for recoverable Bin entries. Original files are never removed by these operations. The existing pending question about auto-clear is not silently resolved by parcel pinning.

Review fixes include a 3D-layer offscreen rendering artifact (replaced with a bounded 2D opening gesture), an immediate-collapse/reopen hover loop, stale preview cancellation across adjacent bags, same-bag archive invalidation, disabled native click handling, search accidentally limiting the menu's recent parcels, and preserving unrelated archive state during Bin expiry. Unfold animation never gates bag visibility on a lifecycle callback; even an initial/offscreen frame has visible targets. Quit is refused during reception as well as preparation/packing.

Final automated evidence: 27 core + 19 app cases, with one app integration skip (45 passed); four licence cases pass. The release bundle is rebuilt and its ad-hoc signature/plist pass validation. A real `ParcelCheck` archive passes `unzip -t` at `/tmp/parcel-courier-archive.7LALXJ/package/`. Current offscreen layouts are in `.build/courier-previews/`: resident courier, chooser, all skins and accessible fallbacks, contents, receiving, packing, ready, small error panel, narrow/wide/minimum hub, Preferences, and populated/empty Bin. These are not compositor-level glass or live pointer tests. Existing compiler deprecation/concurrency warnings remain; no claim of a warning-free build is made.

`Scripts/check-macos.sh` was retried; its isolated native image smoke still stops with Cocoa error 256 opening the generated `opaque.png` through coordinated access. The actual app mention still returns “Computer Use was not approved to use Parcel.” This is not missing authorization from the user. No permission workaround was attempted. This session still exposes `.git` as read-only, and live acceptance is incomplete, so no commit or merge has been performed.

Remaining native gates: Finder/Desktop/browser and promised-file intake, stationary hover targets, cancellation/own-drag lifetime, no focus stealing, persistent courier relaunch, real clipboard copy/paste into Finder, file opening/Quick Look, skin persistence, all Bin confirmations/restore, true glass over varied wallpapers, OS Reduce Motion/Transparency/High Contrast, multiple displays, Spaces/fullscreen and Dock Spring Loading. Only after these are green and Git is writable should the approved merge proceed.

### Earlier verification pass

The follow-up request to run and verify the app repeated the launch, UI-access, Swift-suite, licence-suite and native-smoke attempts. The same native-access restrictions remain. Computer Use permission for Parcel was requested; live testing remains pending that access and successful launch.

Two additional behavioral tests verify that packing errors stay in the shelf instead of triggering a hub alert, and that a removed destination cannot receive files into a different parcel. Both pass. Expanded view review exposed an oversized hero at the 720-by-520 minimum size; the compact hero now leaves Paste and Pack visible. Disabled custom buttons now visibly dim, and disabled native drag surfaces reject accessibility press actions. The follow-up build and signature validation pass.

The follow-up also generated a real archive with `ParcelCheck` and validated it independently with `unzip -t` and Python's `zipfile` CRC check. The archive remains in `/tmp/parcel-qa-archive.wNNwbl/package/`. Preview exports for this review are under `.build/qa-previews/`.

The sandbox also prevents the compiler's normal home-directory caches, nested SwiftPM sandboxing and dSYM generation. Local build commands below keep caches in the workspace, disable only SwiftPM's nested sandbox, and omit debug symbols for this development bundle. The outer execution restrictions remain in force. Normal builds retain their defaults.

## Reproduce

On an unrestricted Mac:

```sh
swift test
bash Scripts/build-macos.sh
bash Scripts/check-macos.sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
open build/Parcel.app
```

The Python licence tests require `cryptography`. To export the review images, set `PARCEL_PREVIEW_DIRECTORY` to a writable absolute directory before running `swift test --filter ShelfPreviewTests`. Artifacts from this session are under `.build/shelf-previews/`.

In this restricted session the successful commands are:

```sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
PARCEL_PREVIEW_DIRECTORY="$PWD/.build/shelf-previews" swift test --disable-sandbox
PARCEL_SWIFT_DISABLE_SANDBOX=1 PARCEL_SWIFT_DEBUG_INFO=none bash Scripts/build-macos.sh
```

Before merge, complete the live Finder/Desktop/browser, file-promise, cancellation, repeated-summon, background focus, Dock, skin persistence/relaunch, Reduce Motion, Spaces/fullscreen and available-display checks from the brief. Inspect all Preferences tabs and the prepare/Pack flows live. Do not treat the offscreen render test or successful compilation as substitutes for that acceptance.
