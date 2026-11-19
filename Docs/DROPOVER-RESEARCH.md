# Shelf research and courier interaction plan

The later requested side-opening redesign and fresh official-video spot-checks are recorded in [Side courier](SIDE-COURIER.md). That revision adds explicitly configured watched folders and non-destructive video preparation while retaining Parcel's local-only scope. It does not claim complete Dropover feature parity or copy its multiple shelf/detail windows.

Research date: 15 October 2026. This is an internal product comparison, not public positioning. Dropover was researched through its published documentation, release notes, App Store listing, and dated user reports; it was not installed or hands-on benchmarked. Claims of superiority below are design goals, not measured results.

## What Dropover does well

- Broad input support and mature in-shelf preview, rename, reorder, ZIP/image actions and native sharing. Its integration coverage (Services, Shortcuts, watched folders, scripting, launchers, widgets and cloud providers) is substantially ahead of Parcel. We should not pretend to match this breadth. [Product](https://dropoverapp.com/), [App Store](https://apps.apple.com/us/app/dropover-easier-drag-drop/id1355679052)
- Global shortcuts and shelf-local shortcuts are separately customizable. Keyboard users can create, select, copy, paste and preview without hunting through the hub. [Keyboard guide](https://dropoverapp.com/kb/shelf-keyboard-shortcuts)
- Docked shelves, non-shake invocation and persistent pinned/recent shelves make it useful beyond an active drag. A permanent Parcel courier must therefore offer real retrieval, not just decoration. [Tips](https://dropoverapp.com/tips)
- Version 5.3 moves action inputs into the shelf, preserves them while switching apps, and moves completion feedback out of the way. This validates keeping our entire fast path in place. Its menu exposes six pinned and three recent shelves, with an All Shelves fallback. [Release notes, 14 September 2026](https://dropoverapp.com/whats-new/5.3.0)
- It is a one-time purchase too, not a subscription competitor. The US App Store currently lists Pro at $7.99, below Parcel's proposed $9.99. Price is not our advantage. [Listing](https://apps.apple.com/us/app/dropover-easier-drag-drop/id1355679052)

## Friction and trade-offs, not unsupported criticism

- Pin creation is documented behind overflow → Shelf Settings → Pin Shelf. Our opportunity is an obvious, always-visible pin on every bag, with pinned-first ordering and labels. Unpinning in Dropover already has a direct pin control. [Pinned shelves](https://dropoverapp.com/kb/pinned-shelves)
- Shelf shortcuts require an active shelf; discovering focus is an extra step. Our nonactivating hover shelf must never imply that it can receive global keyboard input. Buttons and a global summon shortcut remain available. [Keyboard guide](https://dropoverapp.com/kb/shelf-keyboard-shortcuts)
- Dropover retains file references on intake; dragging out defaults to a move on the same volume unless configured otherwise or Option is held. That is native behavior, not a defect, but Parcel's copy-only outbound drag is a more conservative handoff default. Both apps still depend on originals remaining accessible. [FAQ](https://dropoverapp.com/faq)
- The free tier introduces a three-second interaction delay after its 14-day trial. We should not add artificial interaction delays to the courier. [Purchases](https://dropoverapp.com/kb/purchases)
- Cloud is useful, but adds a separate privacy/access surface. Dropover explicitly says intake does not upload automatically. Its policy describes technical/usage data and optional cloud storage; it says cloud files are not encrypted at rest by Dropover. Parcel's local shelf remains deliberately narrower; native Share actions still leave the app at the user's request. [FAQ](https://dropoverapp.com/faq), [Policy](https://dropoverapp.com/privacy-policy)
- A 2024 user discussion requests less persistent shelf clutter and easier global visibility. This is historical qualitative feedback, not proof that current 5.3 lacks those controls: today's docs explicitly include docking and hide/show shortcuts. Likewise an old report of quitting after the last shelf closes may involve another window-management utility; do not label it a current Dropover defect. [Discussion](https://www.reddit.com/r/macapps/comments/1da6x2d/), [Follow-up](https://www.reddit.com/r/macapps/comments/1hcwjaw/)
- Documentation is not perfectly synchronized: the FAQ lists four languages and App Store-only distribution, while 5.3/listing show six languages and the privacy policy discusses website licenses. Prefer the current release/listing for language support; treat distribution plans as unresolved. Do not infer missing accessibility from an unfilled App Store accessibility declaration.

## Parcel gaps found in source

The current popup disappears, so retrieval still needs a shortcut/menu. Bag destinations are rows rather than our satchel art, hover does not reveal contents, only six pieces are shown, file clicks do nothing, and there is no direct file-copy control. Ranking is derived from pinned pieces, with no parcel pin. The popup's opaque skin background does not respect Reduce Transparency explicitly. Repeated selection also clears a just-built archive.

## Implementation priorities

1. A quiet permanent satchel avatar (no wandering, idle loops or notifications), shown on launch. Hover/click unfolds the bags; collapsing never deletes content. Optional visibility control and the existing global shortcut prevent desktop obstruction.
2. Fixed bag targets: top four pinned-first, then recent, plus New. Hover opens a preview below without replacing/repositioning the targets. Dwell is cancellable, not a gate on dropping. Contents remain reachable as the pointer leaves a bag. All pieces scroll; no silent six-item limit.
3. Direct parcel pins, copy-all and per-file copy, click-to-open, Quick Look, reveal, paste and pack. Validate missing sources before mutating the clipboard; errors remain local to the shelf. Keep explicit Open Hub access for everything outside the top four.
4. Anchored, action-driven bag opening and spring reveals; no focus stealing, no dismissal during reception, packing or outbound drags. Glass material with skin tint, opaque Reduce Transparency fallback, and stronger High Contrast borders. Reduce Motion removes transform animation.
5. Backward-compatible parcel pin state, isolated controller/action tests, offscreen layout review at compact/expanded/small sizes and all skins, Swift/package/license checks, then live acceptance when Computer Use is available. Do not claim live tests from offscreen renders.

The user's new request explicitly supersedes the original brief's nonpersistent-avatar restriction. Other boundaries remain: no AI naming, cloud, scripts, clipboard history, watches or widgets; no changes to auto-clear/cache cleanup, no changes to originals, no invented superiority claims. Parcel pins order destinations; existing piece pins still govern existing retention semantics.

## Follow-up: recoverable deletion

The user subsequently requested a delete icon next to pin, confirmation, a Bin, 30-day expiry, and an explicit clear action. This is implemented for parcels: inline confirmation in the courier, confirmation in the hub, whole-parcel restore, 30-day deadline expiry and confirmed individual/whole-Bin permanent removal. Original files are never deleted. Recoverable Bin entries extend the reference set passed to existing cache care; the cache age rules and active-piece auto-clear behavior are unchanged. This is a safety/discoverability improvement, not a claim that Dropover cannot recover content.

## Outcome and honest comparison

Parcel now has the planned persistent courier, visible parcel pins, open-on-hover bags, all-item scrolling, click-to-open, direct copy and paste, nonactivating handoff actions, native glass/fallbacks, and recoverable deletion. The test matrix and blockers are recorded in `COURIER-IMPLEMENTATION.md`. These improvements close specific gaps found in Parcel's source. Dropover remains ahead in integrations, configurable keyboard workflows and field-tested maturity; there is no hands-on evidence yet that Parcel is faster, more stable or categorically better. Cross-app and real compositor acceptance must precede that claim or a release merge.
