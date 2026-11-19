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

Run the **Skippy checks** workflow or use a Mac with Xcode. The workflow builds the universal app, tests the native services, launches it, drives its controls and records the desktop. The keyboard test uses the real global shortcut and public accessibility interfaces. It verifies the front panel’s title after selecting each of the 18 arrows. Its log distinguishes keyboard navigation, native control actions and service tests. [Workflow](../.github/workflows/check.yml) · [Keyboard checks](../Scripts/check-arrow-navigation.swift) · [Hover recorder](../Scripts/record-quiver.swift)

| Interaction | Check |
| --- | --- |
| Unfold and fold | The floating mark stays within one point of its original position during reveal. The backplate passes through intermediate widths when motion is enabled. The strip targets a 220 ms reveal and 170 ms fold. |
| Hover to preview | Allow 230 ms over a tool. Opening a preview uses an ordered-front panel. Crossing a different arrow can replace the preview. A click commits the tool for keyboard use. Screen capture checks that a tool panel appeared after pointer movement alone. |
| Leave and return | A 550 ms delay accommodates the gap to the panel. An open editor survives movement across another arrow. Escape closes the committed panel. |
| Keyboard | Control–Option–Command–P summons Skippy. Command–K searches by tool name. Return opens a match. Ordinary editing keys stay with the active text view. Duplicate shortcuts use physical key and modifiers, and Reset All restores the defaults together. |
| Desktop and devices | The Mac build runs on the macOS runner. The separate device job boots iPhone and iPad simulators and captures their home screens. The application target is macOS. |

The feature inventory and hardware-dependent acceptance cases are in the [Skippy brief](../SKIPPY-BRIEF.md).
