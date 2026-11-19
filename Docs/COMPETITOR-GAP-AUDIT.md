# Parcel competitor gap audit

Research date: 20 October 2026. Product claims below come from the vendors' public product documentation and the open-source Filee/Droppy repositories where available.

## What competitors do especially well

### Droppy

- Multiple invocation choices: notch, cursor, hotkey, and shake.
- Fast action tiles for AirDrop, Mail, Messages, LocalSend, conversion, and cloud handoff.
- On-device OCR for images, screenshots, and PDFs, plus local batch transforms.
- Strong per-display settings, timing controls, and recent OCR history.

Sources: [Shelf](https://getdroppy.app/docs/shelf), [Quick Actions](https://getdroppy.app/docs/quick-actions), [OCR](https://getdroppy.app/docs/ocr), [Transform](https://getdroppy.app/docs/transform), [Settings](https://getdroppy.app/docs/settings).

### Dropover

- Mature in-shelf actions that remain usable while switching apps.
- Instant Actions with preview/cancel, detailed metadata, keyboard copy/paste, Open With, Shortcuts, and Spotlight actions.
- Advanced folder observation rules and delayed batching for files that are still downloading.
- Nearby-cursor shelf placement and strong drag-in/drag-out lifecycle behavior.
- Recent Actions, non-blocking completion receipts below the shelf, pinned and recent shelves in the menu bar, and intelligent local shelf naming in 5.3.

Sources: [Dropover 5.3](https://dropoverapp.com/whats-new/5.3.0), [5.2](https://dropoverapp.com/whats-new/5.2.0), [5.1](https://dropoverapp.com/whats-new/5.1.0), [5.0](https://dropoverapp.com/whats-new/5.0.0), [FAQ](https://dropoverapp.com/faq).

### ShelfyDock

- An immediately understandable Dock-adjacent strip for recent completed downloads and screenshots.
- A compact global search panel with Quick Look and Keep on Shelf.
- Conservative permissions and low idle work.

Source: [ShelfyDock](https://shelfydock.com/).

### Filee

- A contextual radial conversion menu that appears during a modifier-drag.
- Broad format coverage, batch conversion, presets, parallel jobs, conversion route planning, Finder integration, and watched folders.
- Local-first architecture with short-lived drag windows and progress handoff.

Sources: [Filee](https://filee.sh/), [Filee CLI](https://filee.sh/cli/), [Filee source](https://github.com/KnifeLemon/Filee).

## Parcel response

Parcel should not become four applications stacked together. Its advantage remains one persistent, animated courier with one pinned parcel, native Quick Look, local file references, a searchable parcel library, direct Finder Services, and a recoverable Bin.

Implemented from this audit:

- **Contextual local transforms:** images and PDFs now expose only valid actions in the courier, full app, and file context menu.
- **OCR beyond Filee:** image/PDF to searchable Word preserves each source page visually and adds editable text recognized on-device with Apple Vision. OCR text export is also available.
- **Useful document routes:** image to PDF and PDF to PNG/JPEG pages, with cancellable jobs, bounded PDF page counts, non-destructive outputs, and generated files added back to the parcel.
- **Shelfy-style intake without surveillance:** one-click opt-in watchers for completed Downloads and Desktop screenshots. Partial downloads, symlinks, baseline files, and Parcel's own generated outputs are ignored.
- **Existing strengths retained:** cursor-following courier, menu-bar parking, shake restore, four opening directions, dial/grid/list layouts, delayed stable folder intake, Finder Services, file previews, drag-out, search filters, packing, AirDrop, WhatsApp handoff, image/video preparation, and one pinned parcel.
- **Single-surface modifier drag:** the Shift conversion wheel now temporarily suppresses the courier instead of stacking two floating interfaces, then restores the resident courier only after the conversion receipt retracts.
- **Collision-free radial layout:** conversion targets keep a compact footprint while maintaining a clear center cancel zone at every supported action count.
- **Shortcuts and Spotlight:** five App Intents cover courier summon, named parcel creation, file intake, packing with an archive result, and natural search. Parcel and file names are indexed in a private, optional on-device Spotlight index with deep links back to the exact parcel.
- **Editable local presets:** image and video recipes can be saved, renamed, tuned, reused, and removed without touching originals.
- **Per-display memory:** each connected display keeps its own courier anchor, including displays with negative coordinate origins, with a one-click reset and an opt-out for one shared position.
- **Recent-action recall:** the full app exposes the five latest actions and the Shift-drag wheel promotes the most recently used compatible conversion while retaining its fixed six-target cap.
- **Broader-than-competitor naming:** metadata-only smart names work deterministically from macOS 14 onward instead of requiring a newer on-device language model.

Deliberate exclusions:

- No automatic cloud upload or hosted public links: Parcel remains local unless the user explicitly hands a file to another app.
- No general clipboard history: this would read unrelated clipboard data and conflicts with Parcel's narrow privacy model.
- No arbitrary script execution: Finder Services and watched folders remain constrained, inspectable integrations.
- No duplicate floating shelves or multiple pinned parcels: these conflict with Parcel's single-courier interaction model and prior product decisions.

## Remaining optional expansions

- More document routes using sandbox-safe system frameworks or separately installed, explicitly disclosed engines.
- Optional Control Center controls when Parcel adopts an extension-bearing Xcode project rather than a single Swift Package executable.
- User-configurable action tiles beyond the recent-action row, while preserving the compact single-courier interaction model.

## Open Tangerine interaction reference

The current Open Tangerine repository is GPL-3.0-only; only its identified upstream Satsuma material remains MIT. Parcel therefore does not reuse its implementation, mascot, artwork, or source. The independently implemented behavior is limited to the general interaction pattern: hold Shift during an external file drag, show contextual targets at the pointer, create one non-destructive output per input, communicate progress, then retract a successful receipt automatically while leaving failures readable.
