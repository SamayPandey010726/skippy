# Developer handoff — start here

**Handoff date: 13 October 2026.** This ZIP contains the latest selected folder design and the complete authored source for the Parcel macOS utility. It supersedes the earlier box/envelope directions and the unrelated multi-tool MacOS prototype. Start from this folder; do not combine those older prototypes with it.

## What you are taking over

One focused native macOS product: gather files → prepare image copies → pack a clean ZIP → drag, save or share. The selected visual family is a kraft folder with a slate/forest tab, clean sans-serif typography, a restrained small face and a metal paperclip. Contents tuck inside, the cover closes and the clip settles as one finishing gesture. Original local files remain untouched by preparation and packaging.

The code uses SwiftUI/AppKit for the app, ImageIO/Core Graphics for images, ZIPFoundation for archives, CryptoKit/Keychain for licences and SwiftPM for the project. There is no Hammerspoon, Electron runtime or required user account. Minimum deployment target is macOS 14.

**This is implemented source, not a release-certified binary.** The core compiled and passed 19 tests in the original build session; four merchant licence tests and the browser checks passed. Native Swift source syntax was checked. The macOS SDK was unavailable, so native type checking, launch/runtime, performance, signing and notarization are still your first release gates. The included Mac CI has not been run externally. See `Docs/VERIFICATION.md` for the exact boundary.

## First session on your Mac

Extract the ZIP, open Terminal in the `Parcel` folder and use an installed, selected Xcode toolchain:

```bash
swift test
bash Scripts/build-macos.sh
bash Scripts/check-macos.sh
open build/Parcel.app
```

The default bundle is an ad-hoc signed review build with licensing disabled. Fix any macOS SDK/compiler/runtime failures before release work. You may open `Package.swift` in Xcode; the bundle script supplies the Info.plist, icon, resources and signature required for an actual `.app`.

Open `Preview/Parcel-preview.html` in a browser to review the folder artwork and working image/ZIP demonstration. It is self-contained, uploads nothing and needs no server. That preview is a browser implementation; it cannot verify native file promises, AirDrop, Keychain, Quick Look or cross-app compatibility. Native saved collections use the existing sidebar and persistence model; the separate Mac-desktop simulation shown during design review was illustrative and is not a second native app implementation.

## Work ahead, in order

| Priority | Work | Completion evidence |
|---|---|---|
| First | Compile, bundle and run on a Mac; fix SDK/type/runtime problems | All first-session commands pass; app launches with its icon/resources |
| First | Exercise the complete native workflow with real source/destination apps | `Docs/MAC_ACCEPTANCE.md` has recorded results, including file promises, cancellation, missing files, iCloud, images and ZIP extraction |
| First | Finish native animation, keyboard/accessibility and display fit | The approved folder family works at compact size and in the workbench; Reduce Motion, VoiceOver, Spaces/full-screen and focus behaviour checked |
| First | Measure memory, CPU and energy | Idle is quiet; representative large image/archive jobs stay acceptable on real supported Macs |
| Before sales | Choose public name/bundle ID, configure checkout and merchant licences | Production configuration set; valid/invalid/expired licences tested; actual paid order fulfilled correctly |
| Before sales | Sign, notarize and test the hosted download | Developer ID signature and notarization succeed; clean second Mac installs and runs the download |
| Before sales | Publish install/support/refund/update terms and keep tagged source | Customer instructions and a support contact are live; release source and hashes retained |

Exact production commands are in `Docs/DEPLOYMENT.md`. The full manual test matrix is in `Docs/MAC_ACCEPTANCE.md`. Decisions and scope are in `Docs/DECISIONS.md`; research rationale and source links are in `Docs/RESEARCH.md`.

## Configuration you must provide

Your real company bundle identifier, public release name, HTTPS checkout URL, Developer ID Application identity and notarization Keychain profile. Generate a merchant licence signing key outside the repository, and put only its public key into the app. No private key, payment credential, Apple credential or deployed purchase fulfilment service is included.

The proposed price is $20 once with a 14-day trial. Offline signed licence issuance is implemented; payment fulfilment is manual or must be integrated by your merchant-side process. Online activation-count enforcement and automatic updating are not implemented. Users receive a local utility; no hosted sharing service is promised.

## Scope discipline

Keep one folder family and one signature closing interaction. Its movement must follow file/job state and never impose a wait before an already completed ZIP can be used. Keep sounds optional and off by default; do not add an idle animation loop.

The floating folder is explicitly invoked with the menu bar or Control–Option–P. Automatic drag/shake detection, edge docking and a configurable pinning mode were discussed as possibilities, but are not implemented in this handoff. Do not market them until built and tested. Saved named collections are implemented; they reopen unsealed because external sources may have changed. A full immutable ZIP-history browser beyond this existing model would be further work.

This is not full Dropover feature parity. Cloud integrations, OCR, continuous clipboard history, video/PDF optimization and automation extensions are outside this build. Do not add those before the core release gates are complete. The README records supported image formats, source restrictions and cache behaviour so customer expectations match the actual app.

## Repository and files

The requested GitHub repository name is `MacOS`. No repository was created or pushed. You can place the contents of this `Parcel` folder at that repository's root and enable `.github/workflows/check.yml` for Mac compilation/testing.

All original authored source, procedural artwork, icon variants, sample files, tests, release scripts and third-party notices are included. SwiftPM downloads its pinned ZIPFoundation dependency on first build; `Package.resolved` is included. `SOURCE-MANIFEST.json` gives hashes for the shipped source files. Toolchains, compiled build caches, credentials and internal QA screenshots are excluded.

The original code/assets are provided for the commissioning user's commercial development. Preserve third-party MIT notices. Read `COPYRIGHT.md` before deciding public repository licensing.
