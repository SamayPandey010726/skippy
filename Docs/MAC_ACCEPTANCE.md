# Native acceptance before shipping

All rows below are pending native execution. Run on a clean macOS 14 installation and the current supported macOS version. Test Intel and Apple Silicon if claiming universal support. Use harmless fixtures, compare source hashes before/after, and save the results with the release tag.

| Area | Scenario | Expected outcome |
|---|---|---|
| Build | README commands, then production universal build | No compiler errors; icon/resources/privacy manifest included; both architectures present |
| Install | Notarized hosted ZIP/DMG on a second Mac | Gatekeeper accepts; install to Applications; no missing resources |
| Onboarding | Fresh user profile, then relaunch | Clear useful welcome; dismissed state retained |
| Intake | Drag 1 and 100 mixed files; add folder; paste screenshot, text, link | Correct count/content; no silent changes to originals; links are readable text, not fetched pages |
| Promises | Photos/Safari/Mail or another actual promise-producing app | All promised files resolve to the intended box; progress ends; failure is explicit; never seal incomplete intake |
| Duplicate input | Re-add same local file; different files with same name/case/NFC | Same source reference not duplicated; different contents both survive output with numbered names |
| Source access | iCloud placeholder, offline cloud file, denied folder, moved source | Coordinated reads complete or give a usable failure; no incomplete archive; Locate restores missing reference |
| Unsupported sources | Top-level/nested symlink, Finder alias, FIFO | Explicit rejection; no unintended traversal or hang |
| Collections | Rename/reorder/remove; create/switch/delete; quit/relaunch | Names/order persist; original names/files unchanged; restored collection opens unsealed |
| Prepared copies | JPEG/PNG/HEIC; opaque PNG → JPEG; transparent PNG → JPEG | Correct pixels/format/dimensions; opaque works; transparent requires explicit matte |
| Metadata | GPS-bearing JPEG, oriented photo; removal/preservation choices | GPS disappears with removal; orientation correct; original hash unchanged |
| Images | Large dimensions, animated/multipage images, unsupported encoder | Bounded work or clear explanation; originals remain usable |
| Comparison | Prepared image then compare and revert | Both representations shown; reverting uses untouched original; future recipe reads original |
| ZIP | Nested folders, empty folder, Unicode/emoji, dotfiles, metadata opt-out | Independent unzip/Archive Utility reads ordinary data; unrelated hidden content retained |
| Export names | Reserved manifest name, extreme name length, date/note changes | No overwrite; safe readable names; note appears only in intended manifest |
| Destination | Existing file, target inside selected folder, low disk space | Safe refusal/failure; Save confirmation separate; original collection data never overwritten |
| Cancellation | Large copy, ZIP compression, image batch | Stops at safe boundary; partials removed; no ready-looking incomplete ZIP |
| Drag out | One row/multiple selected files/ready ZIP → Finder, Mail, Safari/Chrome upload | Actual files transferred; source action is copy; verify each claimed destination |
| Sharing | Native Share and AirDrop | Actual working copy/ZIP supplied; cancellation harmless |
| Floating panel | Hotkey, menu bar, full-screen/Spaces, other app foreground | Useful panel stays available; no duplicate hotkey toggle; close/reopen works |
| Startup files | Open With from Finder while app closed | File appears once after startup; workbench opens |
| Settings | Packaging changes, sound off/on, login item allow/deny | Valid ZIP invalidation; no recipe race while working; quiet default; error if login registration fails |
| Licence | Production trial, expiry, valid key, modified key, wrong product/key | Keychain persists; paid features obey state; collection remains readable after expiry |
| Recovery | Corrupt/newer JSON; backup-and-reset action | No silent overwrite; backup produced; cleanup disabled while references unknown |
| Cleanup | Referenced child/parent folder and stale unreferenced app copies | References protected; only eligible app-owned copies removed; sources/exported copies untouched |
| Accessibility | Reduce Motion, VoiceOver, keyboard navigation, larger text | State understandable without motion; named actionable controls; usable focus and contrast |
| Efficiency | 30-minute idle, repeated 50-image jobs, large archive | No continuous animation work; measured acceptable CPU/memory/energy; no accumulation of live windows/jobs |

## Native smoke coverage

`Scripts/check-macos.sh` compiles the native app and separately compiles actual service code with `MacSmoke.swift`. It tests resize dimensions, original preservation, opaque PNG conversion, a genuine GPS-containing JPEG, transparency rejection/flattening, PNG export, cancellation and offline licence signatures. It also builds an archive using `ParcelCheck` and runs `unzip -t`.

This does not replace cross-app or accessibility testing. Treat unsupported destinations honestly in the public compatibility list. Native file promises depend on what the source application actually supplies.
