# Verification record

Prepared during the 12 October 2026 build session. This is a source handoff from Linux, not a claim that the native Mac app has passed release acceptance.

| Check | Result | Evidence and boundary |
|---|---|---|
| Portable Swift engine | PASS | Swift 6.0.3, Swift language mode 5; actual dependency resolution and compilation |
| Core tests | PASS — 19 tests | Fourteen packaging tests and five naming/persistence tests; see actual XCTest source |
| Merchant licence tool | PASS — 4 tests | Unicode issuance, tampering, wrong signing key and expiry |
| Actual engine ZIP interoperability | PASS | `ParcelCheck` creates a real archive; independently checked/extracted using Python's standard ZIP reader |
| Standalone browser preview | PASS | Headless Chromium with Playwright: intake, image preparation, real ZIP download, Unicode/case collisions, reduced-motion mode and mobile layout; no page errors |
| Preview archive contents | PASS | Independent CRC/extraction checks and expected prepared JPEG/text/SVG/manifest contents; collision archive retains both input payloads |
| Native Swift source syntax | PASS | Swift parser accepted every app source and `MacSmoke.swift` |
| Native SDK type checking | NOT RUN | Linux has no AppKit/SwiftUI/macOS SDK; syntax checking cannot substitute for a native compile |
| Native app runtime | NOT RUN | Mac drag/drop, file promises, ImageIO, Keychain, hotkey, Quick Look, login item and sharing require Mac execution |
| Native image smoke script | SUPPLIED, NOT RUN | Uses the actual image/licence service source; includes a JPEG fixture asserted to contain GPS before testing removal |
| Signing/notarization/payment fulfilment | SCRIPTS SUPPLIED, NOT EXECUTED | Needs the developer's Apple credentials, production configuration and merchant process |
| Memory/energy/accessibility | NOT MEASURED | Do not publish numbers or compatibility claims until native acceptance |

## Core test coverage

Packaging tests verify extraction and source preservation; explicit metadata cleanup and opt-out; reserved-manifest collisions; missing-source failures and partial cleanup; refusing existing destinations; cancellation before work and after staging; nested symlink rejection; refusing output within an input directory; Unicode/emoji round trips; empty directories; top-level Mac clutter cleanup; and a destination appearing while the job is in progress.

Naming/persistence tests verify traversal/control/separator rejection, canonical Unicode and case collisions, long names with collision suffixes, preservation of missing references and prepared state, and reporting corrupt persistence without rewriting it.

The browser test exercises the self-contained deliverable, not an independently mocked component. Browser image work uses Canvas/fflate, whereas the Mac app uses ImageIO/ZIPFoundation. Passing one does not prove the other. Internal QA screenshots are not part of this delivery.

## Reproduce

On Mac, run the README commands and `Scripts/check-macos.sh`. CI in `.github/workflows/check.yml` supplies the same native build/test stage after the developer commits the source. No external CI job was run during this handoff.

Run the Python issuer tests with `python3 -m unittest discover -s Tests -p 'test_*.py' -v` after installing `cryptography`. For the preview, install Playwright and its Chromium, then `node Preview/check-preview.cjs`. That test creates local verification outputs; they are excluded from source releases.

The acceptance matrix is the remaining release gate. Record failures and fix them before describing the native app as production ready.

## Folder visual revision

The selected direction is now one kraft folder family with slate/forest accents, clean sans-serif display type, a small face without blush, and a metal paperclip. Botanical framing and alternate envelope/cabinet metaphors were removed. Native illustration, icon and standalone preview were updated together. The Mac simulation additionally demonstrates saved folders using the same visual identity; the native app still uses its existing saved-collection sidebar and persistence model.

The revised browser checks passed real Finder-fixture drags, image preparation, cover closure, ZIP download, simulated drag to Mail, saving/reopening collections, panel controls and Reduce Motion. The standalone preview checks also passed. Native source parsing passed; native SDK/runtime verification remains pending. No portable engine or licence behaviour changed in this visual revision.

## Final handoff packaging — 13 October 2026

The latest saved folder source was recovered and repackaged with `START-HERE.md`. Archive integrity, source-manifest hashes, local documentation links, plist parsing, shell script syntax and JavaScript syntax were checked again for this packaging pass. This was not a new macOS runtime or full Swift test run; the earlier test evidence and Mac-only verification limits above remain unchanged.
