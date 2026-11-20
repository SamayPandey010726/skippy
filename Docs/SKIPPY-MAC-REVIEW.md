# Skippy Mac recording library

[Download the offline gallery](../Artifacts/Skippy/Skippy-feature-library.zip). Extract the archive and open `index.html` in a browser. Each interaction has its own H.264 MP4. The archive also contains a GIF of the floating wheel.

## What to look for

| Film | Interaction on the hosted Mac |
| --- | --- |
| Floating wheel | Hover while TextEdit has focus, preview File Shelf, choose Notes, browse More inside the wheel, and fold it again. |
| Keyboard and themes | Change the theme and emblem with shortcuts, navigate two positions from the first pin and open Notes using Return. |
| Settings | Open Settings, switch between Shortcuts and Everyday, then close Settings and summon Skippy again. |
| File Shelf | Open two files into Parcels. Put another file URL on the macOS pasteboard, press Paste and verify its filename on the shelf. |
| Clipboard | Filter the history and recall an older entry after replacing the system pasteboard. Compare its exact text. |
| Extract text | Recognize the words “SKIPPY TEST” in a clipboard image with Vision and check the output. |
| Pick colour | Sample the actual screen and check that the pasteboard contains a six-digit hex colour. |
| Timer | Start a countdown, observe it running and stop it. |
| Notes | Type a note containing a slash and copy the exact text. |
| QR generator and QR scanner | Generate “Skippy QA”, copy the QR image, scan it from the clipboard and compare the decoded payload. |
| Search | Enter a query, press Return, verify Skippy dismisses the panel and the registered browser takes focus. |
| Apps | Pin and unpin the running Finder app. Check that its pin control updates each time. |
| Music | Use the native Open panel to select Glass.aiff and verify the local player shows Glass. |
| Downloads | Find the test document in Downloads, open it and verify the document title in its registered Mac app. |
| Stay awake | Start and release the sleep-prevention assertion. |
| Recent actions | Check the initial empty state on a fresh user account. |
| Mac | Read the actual host OS version from the running app. |
| Calendar | Verify the Connect entry point on a fresh account. |
| Calculator | Enter `(24 + 8) / 2`, copy the result and compare it with `16`. |
| Screenshots | Select a live screen region, copy the joined image and clear the sequence. |
| Draw on screen | Draw a stroke, verify Undo becomes available, undo it and dismiss the overlay. |
| Left, right, top and bottom edges, notch, menu bar and Dock | Each placement has a separate film. Hover its mark, open the first pinned arrow, move the pointer into File Shelf and leave to dismiss it. |

## Environment and evidence

GitHub-hosted macOS 15.8.2 ran the native application. The recording jobs used Xcode 16.4 and ScreenCaptureKit. The runner exposed a 1024 × 768-point desktop. Each silent clip uses a crop of that desktop exported at 1920 × 1080. A stationary final frame holds for the time measured by the recorder. FFprobe checks duration and dimensions after encoding.

On the final regression run at `cb58a23`, XCTest executed **191 tests with zero failures**. The running-app scripts logged **101 passing checks**. The iPhone and iPad simulators both booted. The test suite includes native file conversion, file intake, archive building, persistence, launcher geometry, shortcut handling and macOS integration. The separate running-app checks exercise controls with macOS keyboard and pointer events, Accessibility and the system pasteboard.

- [Final native build, tests, smoke checks, all-arrow UI checks and menu-bar handoff](https://github.com/SamayPandey010726/skippy/actions/runs/44713349413)
- [iPhone and iPad simulator startup and screenshots](https://github.com/SamayPandey010726/skippy/actions/runs/44710559896)
- [Six hosted Mac desktops recording the 22 launcher and tool films](https://github.com/SamayPandey010726/skippy/actions/runs/44710234430)
- [Screen edges, notch placement and menu bar](https://github.com/SamayPandey010726/skippy/actions/runs/44708724224). The initial Dock attempt in this run failed.
- [Passing Dock retest](https://github.com/SamayPandey010726/skippy/actions/runs/44710552014)
- [Search and Downloads handoff retests and the final universal developer build](https://github.com/SamayPandey010726/skippy/actions/runs/44713310659)
- [Focused Settings recording](https://github.com/SamayPandey010726/skippy/actions/runs/44711548477)

## Remaining device checks

The hosted account had no populated calendar or signed-in third-party music service. The clips are silent. Physical speaker output, camera-cutout fit, multi-display transitions and perceived animation smoothness on a ProMotion display still need a hardware pass. iCloud transfer between Mac, iPhone and iPad is on the mobile roadmap. The simulator jobs verify device boot.
