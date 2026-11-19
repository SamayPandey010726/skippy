# Skippy for Mac

Skippy is a quiver of small productivity apps called arrows. File Shelf carries forward the original Parcels idea. The other arrows use the same launcher and open independently. The native app targets macOS 14 and later and runs locally through AppKit and SwiftUI.

## How it opens

Hover over the compact mark to unfold up to five pinned arrows beside it. The mark stays in place. Click an arrow to open a panel beside that icon. Click the mark for the paged workspace. Overflow opens the complete list. The strip folds after 1.8 seconds away and stays available while the pointer moves into the tool panel. Escape closes the panel. The global shortcut and the context menu also open the workspace.

Choose Menu bar, Notch, Floating, Left edge, Right edge, Top edge, Bottom edge or Dock in Settings. Drag the floating mark into position or toward a screen edge to snap. Skippy remembers the display and relative position. The notch mark sits below the camera cutout on equipped displays. In Dock mode, the real Dock tile accepts clicks, files and a secondary-click menu. Optional hover beside that tile uses macOS Accessibility permission to identify its location.

The grid supports five widget sizes, rearrangement, pinning, scrolling in whole pages, native appearance settings, interface scaling and reduced motion. Existing widget preferences and shelf data use their original storage keys.

## Arrow inventory

| Arrow | Capabilities |
| --- | --- |
| File Shelf | Temporarily collect files, folders, images, text and links. Add, drop, paste, copy, open and drag files between apps. Gather named collections, pin a destination, preview files, process copies and pack ZIP archives. |
| Clipboard | Pause capture in Settings. Skippy skips clipboard items marked concealed, temporary or automatically generated. Search up to 200 local text, link, image and file entries. Copy entries back, drag them out, shorten links on request and remove entries. |
| Extract text | Read an image, clipboard image or selected screen area with Vision. Inspect fonts reported for selectable text in a PDF. Summarisation depends on supported Apple Intelligence hardware, OS, SDK and availability. |
| Pick colour | Use the system colour sampler and copy a hex value. |
| Timer | Run a countdown and optionally keep the Mac awake during it. |
| Notes | Edit a quick note and save it on this Mac. |
| QR tools | Generate a QR code, copy it or read a code from an image or selected screen area. |
| Search | Launch a web search. The shelf also supports local filename, type, size and date queries. |
| Apps | Launch or activate apps and pin shortcuts. Saved shell commands require explicit confirmation showing the command before execution. |
| Music | Control supported Music/Spotify playback through Automation or select a local audio file. |
| Downloads | Browse recent downloads and open files. |
| Stay awake | Prevent system/display sleep for a session and restore the usual sleep policy. |
| Recent actions | Review and recall recent file preparation, packing and copying actions. |
| Mac | Inspect CPU utilisation, active/wired/compressed memory, free disk space, network transfer rates, cores, installed memory and uptime. Review notifications delivered by Skippy. |
| Calendar | Request EventKit access and read upcoming events. |
| Calculator | Evaluate arithmetic, parentheses and percentages locally. Invalid expressions and division by zero produce no result. |
| Screenshots | Take multiple screen regions and combine them vertically. For Google Lens, copy the selected region and open Lens for manual paste. |
| Draw on screen | Draw freehand, highlight, add lines, rectangles and ellipses, erase, undo and save a transparent PNG of the annotation layer. |

The shelf's preparation tools cover image resizing, format and metadata controls, video preparation, PDF/text/Word extraction, spreadsheet interchange, Finder Services, file promises, watched folders, conversion presets, ZIP packaging and native sharing. Originals remain in place during conversion.

## Verification and release scope

The project includes native unit and integration tests, macOS smoke checks, bundle/signature validation and a terminal-driven recording of the launched app. The simulator workflow boots iPhone and iPad and captures each home screen. The repository currently ships a Mac application target. The build plan and workflow specify the exact commands. [Implementation plan](Docs/SKIPPY-PLAN.md) · [Workflow](.github/workflows/check.yml)

Hands-on acceptance still covers physical camera-notch and external-display hardware, third-party drag destinations, Dock icon magnification/auto-hide with Accessibility enabled, permission prompts on a clean account, Calendar with real events, media controls with a signed-in player, and longer energy and memory measurements. PDF inspection reports font metadata available to PDFKit. Identifying a font from pixels would need a separately validated recognition method. Automatic upload to Lens and a general feed of other apps' notifications would require a supported integration and explicit privacy design.

The workflow packages an ad-hoc-signed universal developer build for Apple silicon and Intel. Commercial distribution still requires the owner's final bundle/signing identity, notarization, licensing and device allowance validation, fulfilment, an update path, support and clean-install acceptance. The website's waitlist, prices, sender configuration and checkout are separate from the native developer build.
