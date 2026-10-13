# Parcel

A native macOS utility for gathering scattered files, preparing image copies, packing clean ZIPs and sending them. The signature is an original illustrated kraft folder: pieces stack inside it, the cover folds shut, and a metal paperclip settles when the actual archive is ready.

**This handoff contains implemented source, not a notarized Mac binary.** The portable engine compiled and passed 19 tests here. The interactive browser preview passed its workflow tests. This environment is Linux: the SwiftUI/AppKit layer has been syntax checked, but has not been type checked, launched or benchmarked against a macOS SDK. The included Mac CI and smoke checks are the first required developer step. See [verification](Docs/VERIFICATION.md) before treating it as release-ready.

## Start here

For the developer taking over, read [START-HERE.md](START-HERE.md) first. It consolidates the agreed design, exact first build commands, outstanding work and release gates.

Open `Preview/Parcel-preview.html` directly to inspect the visual direction, motion and working local ZIP downloads. It is self-contained and uploads nothing. The example images are original procedural artwork. Browser preview limits are documented below; it is not the Mac executable.

On a Mac with Xcode installed:

```bash
cd Parcel
swift test
bash Scripts/build-macos.sh
bash Scripts/check-macos.sh
open build/Parcel.app
```

You can also open `Package.swift` in Xcode and choose the Parcel executable scheme. The bundle script adds the actual Info.plist, resource files, icon and signature. A raw `swift run Parcel` session is a development executable and is not suitable for distribution.

## Implemented workflow

Gather local files and folders with drag/drop, Open, the menu bar or the floating folder. Explicitly paste images, text or links with Command–Shift–V. Text and links become ordinary UTF-8 text files; linked pages are not fetched and their access permissions are not changed. Native file promises support asynchronous drags where the source app supplies them.

Keep named collections between sessions. Preview with Quick Look, rename ZIP entries without renaming local files, select, reorder, remove and locate missing originals. Control–Option–P toggles the compact floating folder. The panel stays visible across application changes; it is invoked explicitly, not through global drag monitoring.

Prepare selected images or all compatible images as new copies. Resize without upscaling, choose JPEG/PNG/HEIC, adjust JPEG/HEIC quality, and optionally remove embedded metadata. Transparent JPEGs require an explicit white-background choice. Compare original and prepared copies before delivery. Changing recipes starts from the original, avoiding repeated lossy recompression.

Seal a standards-based ZIP using the real files, with optional known Mac-clutter cleanup, date-stamped naming, a recipient note and readable contents manifest. Canonical Unicode and case-insensitive filename collisions get numbered copies. Loose-file drags use the actual local filename; ZIP entries use your parcel names. Drag the ready ZIP to Finder, Mail or a compatible upload target; drag individual prepared/original items separately when that is preferable. Save, reveal, AirDrop and use the native Share menu.

No original local file is renamed, converted or deleted by preparation/packaging. ZIPs are fully built before they are offered for dragging. Partial archives and staging directories are removed on failure/cancellation. Reopening a saved collection requires resealing so a previous session's archive is not silently sent as current work. An already sealed parcel is an explicit snapshot.

## Design and motion

The artwork is original code-based illustration: kraft paper, slate/forest accents, clean display type, a small quiet face and a metal paperclip. The cover closes and the clip settles as one finishing gesture. Active and saved collections use the same folder family; there is no envelope-to-cabinet transformation. The native app renders with SwiftUI shapes and Canvas. It uses finite action-driven springs rather than an idle animation loop. macOS Reduce Motion is respected. A short original paper sound is optional and off by default.

The full workbench separates the collection, the hero folder and practical preparation/sharing controls. The compact panel shares the same state and artwork. Read [design decisions](Docs/DECISIONS.md) for motion timings, colours, architecture and the reasons behind the scope.

## Project map

| Location | Responsibility |
|---|---|
| `Sources/ParcelCore` | Portable collection models, filename policy, safe copying, ZIP creation, manifest and atomic persistence |
| `Sources/ParcelApp/Services` | Mac access/bookmarks, coordinated reads, image processing, licence verification, state, cache care and window/hotkey controller |
| `Sources/ParcelApp/Views` | Workbench, compact panel, illustrated folder, receiving/sending drag surfaces, Quick Look, sharing, preferences and onboarding |
| `Tests/ParcelCoreTests` | 19 meaningful engine tests, including cancellation, collisions and destination races |
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

Choose your public product name and bundle identifier, configure a checkout URL, create a merchant signing key outside the repository, and put only its public key into the app. Production mode enables a 14-day local trial and signed offline licences. A two-personal-Mac allowance can be your sales policy; this build does not implement an online activation-count service.

The issuance tool is functional. Checkout fulfilment is **manual or merchant-integrated**, not an already-deployed webhook/email service: your merchant process must issue and deliver the licence after a verified paid order. No payment credentials or private signing key ship in this bundle. Exact commands and a release checklist are in [deployment](Docs/DEPLOYMENT.md).

The source is intended for your GitHub repository `MacOS` if that is still the desired repository name. It has not been pushed to an external account. The developer can place this folder at the repository root and run the included Mac CI.

## Limits worth knowing

This is a focused file utility, not full feature parity with Dropover's cloud providers, extensions or automation ecosystem. There is no hosted sharing service, automatic clipboard history, whole-disk index, OCR, video/PDF optimization or PDF merger. Arbitrary non-image files, including video and PDF, are collected, previewed and packed unchanged.

Symbolic links, Finder aliases and special files are rejected with an explanation rather than silently followed. Consequently some application/framework/developer folders containing links cannot be packed in this version. ZIPs preserve file data and basic file permissions, not arbitrary extended attributes, resource forks or every Mac filesystem behaviour. This is delivery packaging, not a system backup tool.

Images are normalised to 8-bit sRGB prepared copies. HDR/RAW workflows and animated/multi-page image conversion are outside the preparation scope; send those originals unchanged. Keeping format is supported for JPEG/PNG/HEIC; other inputs require an explicit supported output choice. PNG is lossless and ignores a lossy quality setting. Re-encoding or ZIP compression can make some files larger; inspect the result.

The app supports macOS 14+ with a deliberately light paper appearance. Documented top-level collection limit is 2,000 items; streaming ZIP creation avoids loading whole files into RAM. Native image outputs are bounded to 12,000 pixels on the longest edge and 50 million pixels per image. Actual peak memory, energy and cross-app compatibility must be measured on a Mac; no unmeasured performance claims are made.

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
