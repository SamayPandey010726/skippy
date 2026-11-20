# Skippy

Skippy is a native macOS quiver. Hover over its mark to unfold your pinned tools. Click an arrow for File Shelf, Clipboard, Notes, Timer or another tool. Settings lets you attach the mark to the menu bar, notch, desktop, screen edges or Dock.

[Local Mac handoff and 22-film recording guide](HANDOFF.md) · [Product and feature brief](SKIPPY-BRIEF.md) · [Design and build plan](Docs/SKIPPY-PLAN.md) · [Mac checks](.github/workflows/check.yml)

## Run from a Mac terminal

Use macOS 14 or later with Xcode selected. From the repository root, run:

```bash
swift test
bash Scripts/build-macos.sh
bash Scripts/check-macos.sh
bash Scripts/apple-terminal.sh mac
```

The launcher opens `build/Skippy.app`. Use `bash Scripts/apple-terminal.sh iphone` or `bash Scripts/apple-terminal.sh ipad` on a Mac with the corresponding Xcode simulator runtime to boot a simulator. Skippy itself targets macOS. The default Mac bundle is ad-hoc signed for development.

## Run on GitHub’s Mac

From a terminal authenticated to this repository, dispatch the existing workflow on main. Each run provisions a temporary Mac, executes the build and simulator checks, and attaches the bundle, recordings and device screenshots to the run.

```bash
gh workflow run check.yml --ref main
gh run list --branch main --limit 1
```

## Earlier shelf implementation

The following notes describe the original Parcels shelf and its file pipelines. Current placement, interactions and release status are in the Skippy brief.

## Implemented workflow

Parcel integrates with Shortcuts and Spotlight for courier summon, named parcel creation, file intake, packing, searching and direct parcel opening. Editable image/video presets, per-display courier positions, recent-action recall and private metadata-only smart naming keep repeated workflows fast without uploading file contents.

First-time users get a five-step tutorial covering file intake, hover/click behavior, pinning, previewing, preparation, packing and the global courier shortcut. The default is `⌃⌥⌘P`, avoiding standard macOS and common Command-only actions. It opens the pinned/recent parcel directly for keyboard use: Tab/Shift-Tab moves through files, `/` focuses search, Shift-`/` opens filters, Command-P packs, Command-C copies the focused file, Return opens it and Escape closes. Every in-courier binding and the global chord is editable in Settings → Everyday care.

Gather local files and folders with drag/drop, Open, or the menu-bar shelf. Explicitly paste images, text or links with Command–Shift–V. Text and links become ordinary UTF-8 text files; linked pages are not fetched and their access permissions are not changed. Native file promises support asynchronous drags where the source app supplies them.

Keep named collections between sessions. Preview with Quick Look, rename ZIP entries without renaming local files, select, reorder and locate missing originals. Control–Option–Command–P opens or closes the shelf. Launch stays menu-bar-only; it never opens the main app or a floating courier.

The shelf represents the only pinned parcel, or the most recent if none is pinned. It is a narrow centered notch drawer capped at 40% of the active display in either dimension and supports Dial/Grid/List views. Its glass tint follows Kraft, Night, or Moss. Dial shows only icons and names, loops both ways and scrolls across the whole pane. Native Quick Look opens beside the shelf, supports both scroll axes and closes half a second after leaving both the file and preview. Common actions use a compact toolbar; Prepare is direct.

The top shelf uses native glass, short springs and compact file motion without an idle animation loop. Finder integration appears under selected files' **Services → Send to Parcels**, subject to macOS Services enablement. The menu-bar icon toggles the shelf directly.

Type phrases like `File uploaded on 17th`, `excel or numbers` or `pdf over 10 MB`, or use the type/size/date filter menu. Dates mean added to Parcel; ordinal days use the current month and display the resolved date. Search stays local. Bin is a direct top-bar button. Universal interface size (75–150%) scales the shelf, files, search, hub and Settings together. Dragging files or shaking the mouse opens the shelf on the active display.

The shelf anchors to the top center of whichever display receives the drag or summon, so there is no floating window to reposition.

Each bag has direct pin and delete controls. Deleting a parcel requires confirmation and moves it to Parcel's Bin for 30 days, with Restore, individual permanent deletion and confirmed Empty Bin actions. Only library entries are removed; originals and exports outside Parcel are never deleted. Bin references protect app-held copies until the entry expires or is explicitly removed. Existing piece-pin and auto-clear rules have not changed: parcel pins control ordering, not piece retention.

Prepare selected images or all compatible images as new copies. Resize without upscaling, choose JPEG/PNG/HEIC, adjust JPEG/HEIC quality, and optionally remove embedded metadata. Transparent JPEGs require an explicit white-background choice. Compare original and prepared copies before delivery. Changing recipes starts from the original, avoiding repeated lossy recompression.

Hold Shift while dragging compatible files from Finder or from Parcel to open the sector conversion wheel. Images convert to JPEG, PNG, HEIC, PDF, Word with local OCR or text; PDFs convert to Word/text or page images; Word/RTF/text convert to PDF; CSV, TSV and Excel `.xlsx` interchange and export as a paginated PDF. Every result is created in Parcel-owned storage and added to the parcel—never beside the source—and originals remain untouched. Inspect route-by-route QA copies in `build/Conversion-QA` after running `swift test --filter ConversionMatrixTests`.

Prepare videos as separate MP4/MOV copies with Small/Balanced/High quality and a maximum edge from 480 to 3840 pixels. Originals stay unchanged; orientation is preserved and no upscaling is requested. Output is up to 30 fps. Lower-quality native presets can further reduce resolution; exact byte size or a smaller result is not guaranteed. Unsupported codecs report an error. Use Prepare inside the folder or Prepare videos in the main app's Parcel menu.

Watched folders are explicitly configured in Settings with a destination parcel. Up to eight folders are supported. New top-level arrivals are referenced after a quiet period; baseline files, hidden files, symlinks and partial downloads are ignored. Pausing/removing a watch never deletes source files or parcel entries. No uploads or scripts run. Parcel's own cache and known generated outputs are excluded to avoid loops.

Seal a standards-based ZIP using the real files, with optional known Mac-clutter cleanup, date-stamped naming, a recipient note and readable contents manifest. Canonical Unicode and case-insensitive filename collisions get numbered copies. Loose-file drags use the actual local filename; ZIP entries use your parcel names. Drag the ready ZIP to Finder, Mail or a compatible upload target; drag individual prepared/original items separately when that is preferable. Save, reveal, AirDrop and use the native Share menu.

No original local file is renamed, converted or deleted by preparation/packaging. ZIPs are fully built before they are offered for dragging. Partial archives and staging directories are removed on failure/cancellation. Reopening a saved collection requires resealing so a previous session's archive is not silently sent as current work. An already sealed parcel is an explicit snapshot.

## Design and motion

The artwork uses original code-based satchels, a small quiet face, and kraft, night and moss palettes. Bags unfold with short springs and open on hover; their hit targets never animate away. The courier does not wander or run an idle animation loop. Glass material matches macOS, with an opaque Reduce Transparency fallback and stronger High Contrast borders. Reduce Motion is respected. A short original paper sound is optional and off by default.

The full workbench separates the collection, the hero folder and practical preparation/sharing controls. The compact panel shares the same state and artwork. Read [design decisions](Docs/DECISIONS.md) for motion timings, colours, architecture and the reasons behind the scope.

## Project map

| Location | Responsibility |
|---|---|
| `Sources/ParcelCore` | Portable collection models, filename policy, safe copying, ZIP creation, manifest and atomic persistence |
| `Sources/ParcelApp/Services` | Mac access/bookmarks, coordinated reads, image processing, licence verification, state, cache care and window/hotkey controller |
| `Sources/ParcelApp/Views` | Workbench, compact panel, illustrated folder, receiving/sending drag surfaces, Quick Look, sharing, preferences and onboarding |
| `Tests/ParcelCoreTests` | 51 engine/model cases including natural search, compact/four-way geometry, shake detection, circular slots and packaging safety |
| `Tests/ParcelAppTests` | 82 controller/intake/layout/automation cases including onboarding, Carbon global-shortcut delivery and persistence, App Intents, Spotlight, presets, display placement, native video export and watched-folder events |
| `Tests/test_license_tool.py` | Four issuer/signature tests |
| `Scripts/MacSmoke.swift` | Actual native image/metadata/transparency and licence checks, to run on Mac |
| `Scripts/build-macos.sh` | Local/universal `.app` generation and signing |
| `Scripts/notarize-macos.sh` | Notarization, stapling, assessment, ZIP and DMG generation |
| `Scripts/license-tool.py` | Merchant-side Ed25519 key generation and licence issuance |
| `Preview` | Editable art/CSS/JS, self-contained preview and browser workflow checks |
| `Assets`, `Samples` | Original icon variants and harmless example files |
| `Docs` | Research rationale, decisions, deployment, acceptance matrix and actual verification status |

SwiftPM pins ZIPFoundation **0.9.20**; `Package.resolved` fixes the revision. It is MIT licensed. The native app otherwise uses Apple frameworks. The preview embeds fflate **0.8.2**, also MIT; that JavaScript library is not part of the native engine. Full notices are in `ThirdParty` and the app acknowledgements.

## Production handoff

Choose your public product name and bundle identifier, configure a checkout URL, create a merchant signing key outside the repository, and put only its public key into the app. Production mode is locked until a signed offline licence includes the current Mac ID. Licence payloads enforce the sold one-, two- or five-Mac allowance; adding a later Mac requires reissuing the signed key.

The issuance tool is functional. Checkout fulfilment is **manual or merchant-integrated**, not an already-deployed webhook/email service: your merchant process must issue and deliver the licence after a verified paid order. No payment credentials or private signing key ship in this bundle. Exact commands and a release checklist are in [deployment](Docs/DEPLOYMENT.md).

Changes remain on `feature/shelf-share-licensing` until live UI acceptance permits the approved commit and merge. Local Git writes and GitHub authentication are now verified working. See the verification record rather than assuming an implementation pass has been committed or merged.

## Limits worth knowing

This is a focused file utility, not full feature parity with cloud providers, extensions or automation ecosystems. There is no hosted sharing service, automatic clipboard history, whole-disk index, video/PDF optimization or PDF merger. Arbitrary non-image files, including video and PDF, are collected, previewed and packed unchanged. The internal [shelf research](Docs/DROPOVER-RESEARCH.md) documents product strengths, trade-offs and remaining gaps without claiming unmeasured superiority.

Symbolic links, Finder aliases and special files are rejected with an explanation rather than silently followed. Consequently some application/framework/developer folders containing links cannot be packed in this version. ZIPs preserve file data and basic file permissions, not arbitrary extended attributes, resource forks or every Mac filesystem behaviour. This is delivery packaging, not a system backup tool.

Images are normalised to 8-bit sRGB prepared copies. HDR/RAW workflows and animated/multi-page image conversion are outside the preparation scope; send those originals unchanged. Keeping format is supported for JPEG/PNG/HEIC; other inputs require an explicit supported output choice. PNG is lossless and ignores a lossy quality setting. Re-encoding or ZIP compression can make some files larger; inspect the result.

The app supports macOS 14+ with three skins, including a dark style. Documented top-level collection limit is 2,000 items; streaming ZIP creation avoids loading whole files into RAM. Native image outputs are bounded to 12,000 pixels on the longest edge and 50 million pixels per image. Actual peak memory, energy and cross-app compatibility still require live measurement; no unmeasured performance claims are made.

Generated copies live under `~/Library/Application Support/Parcel`. Referenced copies are retained. Unreferenced app copies older than 30 days are eligible for startup cleanup; the explicit preferences action cleans unreferenced copies older than a day. Original files and exported copies outside the app-owned directories are excluded. Important externally dropped/clipboard content should be saved out if you remove its parcel and need it permanently.

The browser preview keeps collections only for that session, accepts individual files, uses JPEG/PNG canvas conversion, and limits packages to 100 MB. It cannot reproduce native file promises, Finder drags, Keychain, HEIC encoding, Quick Look or AirDrop. The Mac implementation supplies those behaviours.

## Developer checks

```bash
swift test
bash Scripts/check-macos.sh
python3 -m pip install cryptography
python3 -m unittest discover -s Tests -p 'test_*.py' -v
```

For browser checks, install Playwright in your developer environment, install its Chromium browser, then run `node Preview/check-preview.cjs`. If Playwright is outside normal module resolution, use `PARCEL_PLAYWRIGHT` with its module path; `PARCEL_CHROME` can point to a local test browser. See `Docs/MAC_ACCEPTANCE.md` for the native end-to-end checks that cannot be replaced by unit tests.
