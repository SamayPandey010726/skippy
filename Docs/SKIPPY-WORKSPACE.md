# Skippy for macOS

Skippy groups 21 tools, called arrows, behind Scout. This build uses the approved blue-grey appearance. The developer app targets macOS 14 or later on Apple silicon and Intel.

## Scout, More and Quick Pins

- Hover over Scout to reveal Quick Pins that are set to appear on hover. When Quick Pins are configured, the floating hover state prioritizes those shortcuts. Click Scout to open the searchable drawer, or use the launcher shortcut to reveal the primary arrow controls and **More**. Hover over an arrow for a preview and click to open for editing. Use the panel’s pin button to keep it visible.
- **More** opens the searchable **Drawer**. Type a name, use Up and Down to select, Return to open, and Escape to return. The icon grid remembers the search. Use the pin beside the selection or secondary-click a tile.
- **Settings → Placement** offers Floating, Left edge, Right edge, Top edge, Bottom edge, Notch, Menu bar and Dock. Drag Scout toward an edge to preview the attachment. Release to settle. Use **Detach to floating** from the secondary-click menu. The Dock uses Skippy’s actual app tile. Dock hover requires Accessibility permission.
- **Settings → Pins** lets you reorder shortcuts, assign a position and choose **On hover**, **Always visible** or **Use default**. Drag a pin anywhere within the display to reposition it. Skippy saves its offset on that display. **Show connector lines** links Scout to its pins and active card. The first three can appear around Scout. Attached strips prioritize Quick Pins. Additional pins live in More.
- **Settings → General** controls the launcher emblem, scale, launch at login, launcher hover and tool previews. **Settings → Privacy** shows capture, clipboard and accessibility options. The app follows macOS Reduce Motion.

## Keyboard shortcuts

Edit system-wide and local shortcuts in **Settings → Shortcuts**. Use Escape to cancel recording. macOS may reserve a combination or another app may have registered it. Select a replacement if Settings marks a shortcut unavailable. Existing custom selection and in-app shortcuts carry over.

| Action | System-wide default |
| --- | --- |
| Expand Scout | ⌘⇧S |
| Send selection to Skippy | ⌃⌥⌘P |
| File Shelf | ⌃⌥⌘F |
| Clipboard | ⌃⌥⌘C |
| Extract text | ⌃⌥⌘E |
| Pick colour | ⌃⌥⌘I |
| Temporal | ⌃⌥⌘T |
| Notes | ⌃⌥⌘N |
| QR tools | ⌃⌥⌘Q |
| Search | ⌃⌥⌘S |
| Quick Launch | ⌃⌥⌘A |
| Music | ⌃⌥⌘M |
| Downloads | ⌃⌥⌘D |
| Stay awake | ⌃⌥⌘W |
| Recent actions | ⌃⌥⌘R |
| Mac | ⌃⌥⌘Y |
| Calendar | ⌃⌥⌘L |
| Calculator | ⌃⌥⌘K |
| Screenshots | ⌃⌥⌘4 |
| Draw on screen | ⌃⌥⌘B |
| Convert files | ⌃⌥⌘V |
| Compress files | ⌃⌥⌘Z |
| Extract archive | ⌃⌥⌘X |

| Action | While Skippy has focus |
| --- | --- |
| Search arrows | ⌘K |
| Browse the visible launcher arrows | ⌥⇧B |
| Move through launcher buttons | Arrow keys or Tab / Shift-Tab |
| Open selected arrow or More | Return or Space |
| Close the current panel | Escape |
| Open Settings | ⌘S |
| Change emblem | ⌥⇧I |
| Next or previous widget page | Tab / Shift-Tab |
| Search files or show filters | Slash / Shift-Slash |
| Pack the parcel | ⌘P |
| Copy or paste shelf items | ⌘C / ⌘V |
| Open focused file | Return |
| Open Clipboard / widgets / media preparation | ⌥C / ⌥T / ⌥P |
| Copy image text with OCR | ⌘⇧O |
| Undo or redo while drawing | ⌘Z / ⌘⇧Z |

## Parcels and the File Shelf

- Drag, paste or add files, folders, links and clipboard items. Command-click several shelf items and select **Stack selected**. Click a stack to expand, rename, reorder or ungroup it. Drag the collapsed stack to pass its available members as separate items.
- Open **Convert files**, **Compress files** or **Extract archive** from More or via their shortcuts. You can also secondary-click a shelf item or use Convert and Compress from Finder’s **Services** menu. Choose, paste or drop source files. The converter lists formats compatible with the selection.
- The converter handles image copies and PDF or OCR output, PDF page images and text, Office/text to PDF, smaller MP4 copies and interchange among CSV, TSV, XLSX and table PDF. Numbers-to-XLSX uses Apple Numbers and macOS Automation. Check the result when source formatting, formulas or multiple tables matter.
- Compress to ZIP or TAR.GZ with system tools. Install 7-Zip for 7z creation or RARLAB’s RAR tool for RAR creation. Skippy verifies the archive before adding it to the shelf. The built-in Extract arrow handles ZIP.
- Results land in the File Shelf. **Show in File Shelf** opens a separate destination window and highlights the result. An operation started from a file’s context menu opens beside that window. Copy, drag, reveal or save copies to another folder. When a single-file result is saved and validated, **Original** offers an explicit Trash action. If the output uses the original extension, it also offers atomic replacement with a sibling backup. Failed or cancelled work does not expose source actions.

## Quick Launch, Temporal, Calculator and markup

- Open **Quick Launch** to run the default browser, default mail app, or another saved Mac app. **+** opens the Applications picker. Secondary-click an app icon to move, replace or remove its shortcut. Names appear on hover or keyboard focus.
- **Temporal** lets you start, pause, resume or stop a countdown, change it by five minutes, and keep the Mac awake during the timer.

- Hover over Calculator for a preview. Click its arrow or use ⌃⌥⌘K for an editable panel. Type an expression or use the keypad. **Scientific** opens a second key bank with trigonometry in radians, square roots, logarithms, powers, factorials and constants. Hover reads the last result without taking keyboard focus. The clock icon opens recent calculations. Return or the equals key evaluates. **Copy** copies the answer.
- Open **Draw on screen → Start drawing**. Choose pen, highlighter, line, rectangle, ellipse or eraser. Adjust colour and width. Use **Interact** to work in the apps below the ink, then **Resume drawing** to return.
- In the drawing toolbar choose **Capture → Area, Window, Display or Multiple**. Multiple lets you draw several crops in one session and opens a live grid composer beside the canvas. In **Screenshots**, reorder or remove regions, select Stack or Grid, and copy or save a PNG. The capture compositor adds the strokes to the selected region at native pixel scale.

## GitHub build and evidence

**Skippy checks** runs the native tests and produces the universal developer bundle and a WindowServer recording. **Record Skippy on Mac** with the `connected_walkthrough` input records one continuous desktop session and uploads the same universal app used in the recording. **Record Skippy attachments** records attached placements.

The developer ZIP uses an ad-hoc signature. Release distribution requires the owner’s Developer ID signature and notarization. The hosted Mac uses a virtual display. Physical notch placement, external display scales, fresh-account permissions and signed-in Music or Spotify playback require a matching environment.
