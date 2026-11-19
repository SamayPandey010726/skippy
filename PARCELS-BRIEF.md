# Parcels — product and development brief

Updated 19 November 2026. This is the current handoff for the work in this repository. Earlier documents describe previous product directions and may no longer match the current notch design.

## Product vision

Parcels is being developed as a native macOS productivity hub attached to the top of the screen. A compact notch opens into a customizable widget workspace, inspired by the immediacy of Fenn and NotchPixel while using macOS controls, materials and permissions. The original Parcels file shelf is one tool within this hub, rather than the entire application. A separate Settings window remains available. The ambition is a polished, playful, accessible experience with hover, mouse and keyboard support.

This is proprietary software under active development. It is not a finished or independently verified commercial release. iPhone and iPad support are future possibilities, not implemented products.

## Repository and hosting

- Private GitHub repository: <https://github.com/SamayPandey010726/parcel>.
- Primary branch: `main`.
- The macOS source and the website live in the same repository. The app is a Swift package, with a script that assembles a macOS application bundle. The React/Vite website is in `website/`.
- No public website deployment or download host has been confirmed as part of this handoff. The GitHub Pages API returned 404 for this repository when checked; that does not establish whether another host exists.
- The website README documents local preview and a temporary tunnel. Production hosting, a domain, a verified Resend sender, checkout and download distribution must be configured and checked separately.

## Current state of the app

The current notch revision contains code for a paged mixed-size widget dashboard, persistent widget sizes and ordering, pinned circular shortcuts, a menu-bar-resident panel, adjustable shortcuts, theme and accessibility settings. It incorporates an existing local file shelf, clipboard history, search, image and document preparation/conversion paths, QR generation and scanning, text extraction, colour sampling, timer, notes, music controls, app launcher, downloads, recent actions and a basic Mac information panel.

Recent unverified additions include screen-area OCR and QR scanning; multi-region screenshot collection and vertical composition; a basic arithmetic calculator; EventKit calendar access and upcoming events; a drawing overlay with pen, highlighter, lines and shapes; optional stay-awake while the timer runs; app pinning; and saved shell commands with a confirmation dialog. The Google Lens flow currently copies a selected screen region and opens Lens for the user to paste; it does not automatically upload the image.

These statements describe code present, not a guarantee that each feature works. This revision has not been built, launched or tested since the latest changes, at the owner's request. Some earlier implementations and legacy views remain in the source. File shelf behaviors, conversions, permissions, keyboard shortcuts, drag and drop, panel positioning, pinned hover, visual quality and persistence all require fresh verification on a Mac.

## Remaining product and engineering work

- Finish and validate the compact widget-first design, drag/reorder interactions, hover corridors, pin overflow, page snapping, animations, reduced-motion behavior and multiple-display/menu-bar placement.
- Verify every widget and shortcut in realistic use, including external application drag and drop, clipboard history, conversions and error handling. Measure responsiveness, memory, CPU and energy use.
- Complete richer CPU, RAM, disk and network monitoring, a reliable font detector, drawing eraser/export, and any required automatic Lens integration. The current calculator is basic arithmetic and screen capture composition is vertical.
- Determine an appropriate supported design for third-party notification mirroring. The public `UNUserNotificationCenter` delivered-notifications API exposes the calling app's own notifications, not a general feed of every Mac app.
- Review screen-recording, Calendar, Accessibility, Automation and other permission prompts and privacy implications. The documented EventKit flow requires full calendar access to read events.
- Audit shell macros and clipboard privacy, sandbox/distribution requirements, third-party licences, data retention, first-run onboarding and crash recovery.
- Design and verify the commercial release process: signing, notarization, final bundle ID, licensing and device allowance, purchase fulfilment, customer support, updates and clean-install testing.

The detailed design and provisional feel audit are in [Docs/NOTCH-FEEL-AND-SCOPE.md](Docs/NOTCH-FEEL-AND-SCOPE.md). Competitive research and earlier product explorations are in `Docs/`; the older README and deployment guidance contain historical claims and should not be taken as a current test report.

## Architecture and key files

| Location | Purpose |
| --- | --- |
| `Sources/ParcelApp/Services/DropPopup.swift` | Notch panel, placement, hover and keyboard routing. |
| `Sources/ParcelApp/Services/NotchTools.swift` | Widget tool state and views. |
| `Sources/ParcelApp/Services/NotchWidgets.swift` | Widget sizes, order, pinning and page layout. |
| `Sources/ParcelApp/Services/ScreenMarkup.swift` | Screen annotation overlay. |
| `Sources/ParcelApp/Services/NotchCalculator.swift` | Local arithmetic parser. |
| `Sources/ParcelApp/Services/ClipboardHistory.swift` | Clipboard history. |
| `Sources/ParcelApp/Services/ParcelStore.swift` | Shelf state and item operations. |
| `Sources/ParcelCore` | Collection models, file packaging and core logic. |
| `Sources/ParcelApp/Views` | Native SwiftUI and AppKit views and bridges. |
| `Tests` | Existing unit and integration tests; presence does not imply they pass. |
| `website` | React/Vite marketing site, interactive demos and waitlist endpoint. |
| `Scripts/build-macos.sh` | Development or production app-bundle assembly. |

The native package targets macOS 14 and later, uses Swift and Apple frameworks, and pins ZIPFoundation 0.9.20. The website uses React, Vite and TypeScript. The current development bundle configuration disables production licensing; the website's one-time pricing is $2.49 for one Mac, $4.99 for two and $9.99 for five, with checkout not yet connected according to its README. Resend integration code exists, but deployment and credentials are not verified.

## Developer commands

After the owner authorizes testing, from a Mac with Xcode and the selected command-line toolchain:

```bash
cd /Users/jimishakansara/FirstVentures/parcel
swift test
bash Scripts/build-macos.sh
bash Scripts/check-macos.sh
open build/Parcel.app
```

The build script replaces its generated `build/Parcel.app` bundle. Inspect the script and signing settings before running it; do not treat the development build as a release. For a local website preview:

```bash
cd /Users/jimishakansara/FirstVentures/parcel/website
npm install
npm run dev
```

See [website/README.md](website/README.md) for server-side waitlist configuration and [Docs/DEPLOYMENT.md](Docs/DEPLOYMENT.md) for historical release instructions, while reconciling both with the current implementation before deployment. Never commit production signing keys, API secrets or customer data.
