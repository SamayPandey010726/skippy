# Product and engineering decisions

## The chosen product

One integrated file utility. The core task is gather → prepare → pack → send. The functional baseline combines file shelves and sharing, clean package creation and the FilePane user's wish for convenient conversions/compression with predictable originals and fewer save prompts. Animation is the signature interaction, not a substitute for those jobs.

The research established competition and qualitative demand in this niche. It did not establish a vacant category or prove that our exact interaction will convert at $20. Dropover, Yoink, Historr and PackMint already cover substantial portions. This implementation deliberately concentrates on a coherent local workflow and original visual character.

## Why SwiftUI + AppKit

SwiftUI supplies ordinary views, state binding and springs. AppKit supplies real pasteboards, file promise receiving, multi-file drags, floating panels, Quick Look, sharing and the global hotkey. This avoids Hammerspoon installation, Electron, a web runtime and a background service stack on the user's Mac. No private system APIs are used.

The portable `ParcelCore` library contains the parts whose safety can be tested without macOS. The native services use ImageIO/Core Graphics, PDF/image previews through Quick Look, CryptoKit, Security and Carbon's registered hotkey. Foundation coordinated reads are used on Mac when creating the input snapshot. All user file preparation is local.

## The illustrated folder

The folder is original artwork rather than a licensed film character. Kraft paper, a slate/forest tab, metal clip and a restrained little face supply the character. Botanical framing and blush details were removed. Avenir Next handles display type; system type handles controls. Saved collections stay in the folder family.

Motion has a purpose. Arrival produces a short spring; the papers tuck inside as the cover closes. The fold takes approximately 460 ms; the paperclip settles after successful ZIP completion. The native view uses a 0.46-second ease-out for the cover and a short damped spring for the clip. No idle timer drives decorative animation. Reduce Motion removes the movement while preserving state feedback. Sounds are opt-in.

The workbench exposes useful actions without hiding them inside the illustration. The folder receives drops and drags the collection; rows provide selection, preview, ZIP-entry rename, remove and individual drag-out. Loose-file drags retain their actual filename; prepared copies get a readable name when generated. The compact panel shares the exact collection and jobs. Mouse-free alternatives are Open, paste, menu commands, Save, native Share and keyboard shortcuts. VoiceOver, contrast and focus behaviour still need native acceptance testing.

## Source and prepared representations

A `ParcelItem` records its original reference plus an optional prepared-copy reference. Preparation always reads the original, not the previous lossy result. Reverting representation clears the prepared reference; it does not rewrite the original or immediately destroy a cached copy. Explicit metadata and transparency choices belong to the image recipe.

Saved bookmarks keep selected sources accessible between sessions. Missing items remain in the collection so users can locate them instead of losing references silently. Source access is retained while referenced and released when the last collection reference is removed. Private library JSON necessarily contains local paths/bookmarks; manifests contain output names and sizes, not those paths.

Text and links are explicitly captured, stored as UTF-8 files and delivered without a receiver needing our app. There is no clipboard watcher or browser-tab scraping. A link remains a link; packaging it does not bypass the source service's permissions.

## Packaging safety

Core staging uses one owned temporary job directory. Files are copied in bounded 1 MiB chunks. Special files, symbolic links and aliases are rejected. A file whose size or modification date changes during its copy causes failure. Directory nesting is bounded. Original writes never occur in these operations.

Filename validation rejects traversal, control characters and unsupported separators. Names use canonical Unicode and a case-insensitive collision key; numbered copies prevent silent replacement on common receiving filesystems. This policy also applies within copied folders. A contents-manifest name is reserved and real inputs with that name are disambiguated.

Known `.DS_Store` and `__MACOSX` clutter is an explicit ZIP option. Other hidden files are not silently removed. Packaging preserves ordinary data and basic permissions. Mac extended attributes/resource forks and symlink-preserving application distribution are not advertised.

ZIPFoundation is pinned, permissive and already implements Deflate/ZIP64 instead of adding a custom archive format. The archive is created beside the destination under a unique partial name, closed, checked for expected entry count, then moved to its final name. Publication is atomic relative to the destination filesystem. Existing destinations are not overwritten by the engine, including a file that appears during the job. A Save-panel replacement is a separate explicitly confirmed action, with an additional guard against overwriting original collection data.

Staging and partial outputs are cleaned on failure/cancellation. A completed archive is a snapshot, not a live view of externally editable files. A restored collection always reopens unsealed, requiring resealing before sending fresh work. Large copy/encode operations can take time; cancellation checks exist between copy chunks/entries and between image stages. ImageIO's current encoding call cannot be interrupted internally.

## Images

ImageIO supplies decoding and JPEG/PNG/HEIC encoding. The longest-edge cap does not upscale. Output is 8-bit sRGB with orientation normalised; original wide-gamut/HDR data remains untouched. Alpha channels are checked for actual transparency before rejecting a JPEG conversion, so opaque PNGs are supported. A white matte requires an explicit choice.

Metadata removal is separate from ZIP clutter cleanup. Default prepared images remove metadata, including location. When preservation is requested, orientation metadata is updated for the transformed image. PNG is lossless; quality is meaningful only for lossy formats. Some outputs can be larger. The UI offers original/prepared inspection rather than claiming a guaranteed percentage reduction.

## State, recovery and cache care

Library persistence uses atomic JSON writes with a version field. Corruption or a newer unsupported schema is reported; the file is not silently replaced. The recovery action backs it up before creating a fresh library. Cleanup is disabled while the library cannot be read, avoiding deletion of unknown references.

Only app-owned Prepared, Received and Exports directories are candidates for cache care. References to a child or to an enclosing folder protect it. Startup cleanup considers unreferenced data older than 30 days; the explicit preferences action uses a one-day grace period. No directory outside those ownership boundaries is removed.

## Commercial scaffolding

The developer bundle defaults to licensing disabled so it can be reviewed. Production mode requires a company bundle identifier, HTTPS checkout URL, Ed25519 public key and Developer ID signing identity. A local Keychain trial record supplies 14 days of preparation/packaging/sharing. Saved references remain readable after expiry.

An offline licence is a base64url JSON payload plus Ed25519 signature. Only the public key is in the app. The merchant-side CLI generates/holds the private key and issues the token after verified payment. This handoff contains no deployed payment webhook or mail sender. There is no online device-count enforcement, server revocation or tamper-proof DRM claim. Those are explicit business tradeoffs for a small perpetual utility.

## What is intentionally outside this release

Hosted sharing, external cloud-provider integrations, whole-disk search, OCR, continuous clipboard history, video/PDF compression and PDF merging would require additional workflows, permissions, services and QA. They are not required to demonstrate the chosen task. The latest instruction removed an arbitrary LOC cap; implementation scope remained tied to the agreed useful workflow rather than adding unrelated modules.

## Verification boundary

Portable Swift compilation/tests, independent ZIP extraction, issuer tests and browser preview checks ran here. Native UI/type checking, actual ImageIO results, cross-app file promises, login items, Keychain trial behaviour and notarization require a Mac. The included CI and native smoke source cover part of that work; the acceptance matrix covers the interactions that need human/native testing. Shipping is conditional on those checks passing.
