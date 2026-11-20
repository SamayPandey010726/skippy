# Skippy interaction review

## What the references show

| Product | Observed interaction | Decision for Skippy |
| --- | --- | --- |
| [DuoBar](https://www.linkedin.com/pulse/hiding-menu-bar-icons-never-worked-me-so-i-merged-them-teekam-suthar-lhxof) | In the 30 fps LinkedIn video, around 10–13 seconds, the pointer rests on the combined status mark. Wi-Fi stays under the pointer as memory and battery appear beside it. Moving away folds the icons back into the mark. | Keep one stable pointer target. Animate the width of the actual strip and its glyph positions together. On a screen edge the strip opens toward the available space. |
| [Droppy](https://github.com/1of1Adam/Droppy) | The Mac demo moves between compact media, an expanded shelf and desktop files. The surface stays attached while the pointer crosses between its parts. | Allow a short handoff from an arrow to its panel. Clicking a preview keeps the tool open for editing. |
| [Fenn](https://fenn.click/) | Its interactive Windows demo opens a glass pill into a grid with tiles of different sizes. A timer, media, a note and clipboard entries can be recognized at a glance. | Keep pinned tools on the strip, retain the customizable grid and give every tool a searchable keyboard route. |
| [NotchPixel](https://notchpixel.com/) | The Windows music demo expands from a small status strip to a translucent media card with artwork, scrubber and playback controls. | Keep a familiar icon and title between compact and expanded states. Reveal controls inside the panel and honor system Reduce Motion. |

These are observations of the vendors’ public demonstrations. The transition timings below are Skippy’s own settings. A comparative latency or energy benchmark would require running the products on the same hardware.

## Reproducing the checks

Run the **Skippy checks** workflow or use a Mac with Xcode. The workflow builds the universal app, tests the native services, launches it, drives its controls and records the desktop. The keyboard test uses the real global shortcut and public accessibility interfaces. It verifies the front panel’s title after selecting each of the 18 arrows. The runner captures each arrow from its native window. It also relaunches with the Menu bar setting, moves the pointer from the real status item into its shelf and checks that leaving both releases the space. Its log distinguishes keyboard navigation, native control actions and service tests. [Workflow](../.github/workflows/check.yml) · [Keyboard checks](../Scripts/check-arrow-navigation.swift) · [Hover recorder](../Scripts/record-quiver.swift)

| Interaction | Check |
| --- | --- |
| Unfold and fold | The floating mark stays within one point of its original position during reveal. The backplate passes through intermediate widths when motion is enabled. The strip targets a 220 ms reveal and 170 ms fold. |
| Hover to preview | Allow 230 ms over a tool. Opening a preview uses an ordered-front panel. Crossing a different arrow can replace the preview. A click commits the tool for keyboard use. Screen capture checks that a tool panel appeared after pointer movement alone. |
| Leave and return | A 550 ms delay accommodates the gap to the panel. An open editor survives movement across another arrow. Escape closes the committed panel. |
| Keyboard | Control–Option–Command–P summons Skippy. Command–K searches by tool name. Return opens a match. Ordinary editing keys stay with the active text view. Duplicate shortcuts use physical key and modifiers, and Reset All restores the defaults together. |
| Desktop and devices | The Mac build runs on the macOS runner. The separate device job boots iPhone and iPad simulators and captures their home screens. The application target is macOS. |

The feature inventory and hardware-dependent acceptance cases are in the [Skippy brief](../SKIPPY-BRIEF.md).

## Tool acceptance cases

| Arrow | What to verify |
| --- | --- |
| File Shelf | Open the sample text and image through Launch Services and read their filenames from the shelf. Native service tests cover file promises, paste, preview, conversion and ZIP contents. |
| Clipboard | Capture disposable text from the system pasteboard, find it by query, copy it from history and compare the pasteboard. Concealed and paused fixtures must stay out of history. |
| Extract text | Write a generated image containing “SKIPPY TEST” to the system clipboard. Run Extract text and read the recognized words back. |
| Pick colour | Activate the native sampler and click a screen pixel. Verify that the clipboard contains a six-digit hex value and the next arrow can open. |
| Timer | Start a countdown and stop it from the running app. |
| Notes | Select everything in a populated note, type a replacement containing a slash, copy the note and compare the entire string. A separate persistence test reloads a note. |
| QR tools | Type a payload, copy the generated QR image, scan the clipboard and compare the actual decoded string. |
| Search | Edit a query in the running app. Verify URL construction for spaces, literal plus signs, ampersands and Unicode. |
| Apps | Find the running Finder, pin it, unpin it and verify the control returns to its original state. |
| Music | Check the local playback control. Load an Apple-provided AIFF through the native player and check its playback or output-unavailable state. |
| Downloads | Create a disposable download and find it in the view. Test date ordering, the twelve-file limit and directory exclusion in a separate fixture. |
| Stay awake | Start and release a real sleep-prevention session through its two control states. |
| Recent actions | Read the activity list or its empty state. Store tests check recency, retention and ranking of repeatable conversions. |
| Mac | Read the host's actual OS version from the live panel. |
| Calendar | Verify the Connect action on a fresh account. Populated calendars need an account with consent. |
| Calculator | Enter “(24 + 8) / 2”, copy the result, and compare the pasteboard to “16”. |
| Screenshots | Drag a region with the system capture tool, copy the joined image and clear the sequence. A separate test checks two input sizes and the final dimensions. |
| Draw on screen | Open the native overlay, draw a stroke, verify Undo becomes available, undo it and close the overlay. |

Public demo videos and a hosted Mac cannot establish comparative performance on physical MacBook displays. Dock magnification, a physical camera cutout, third-party player accounts, populated calendars and the audible output of the runner remain separate acceptance cases.


## Feature recordings

On a disposable macOS 15 or newer GUI account, run `bash Scripts/record-feature-library.sh` with Xcode, ffmpeg, Accessibility and Screen Recording available. The driver changes the test account's clipboard and Skippy preferences and opens sample files. It exercises the running application through Quartz and Accessibility and records its windows through ScreenCaptureKit. The tests create their own Downloads fixture and keep captures in a fresh build directory.

The review index contains an MP4 and poster for each arrow, with separate films for QR generation and scanning, and additional films for the wheel, keyboard and themes, and Settings. The exporter checks every clip for 1920 × 1080 resolution and 15–20 seconds of playback before publishing the index. A 16:9 section of the runner display is framed around the interaction; encoded resolution and the native display scale are distinct. Calendar on an empty account shows the connection control. Playback on a headless account can verify loading a file without verifying physical audio output. [Film driver](../Scripts/record-feature-library.sh)
