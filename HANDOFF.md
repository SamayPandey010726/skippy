# Skippy for Mac · local test handoff

Start with the build from source, check the floating wheel by hand, then run the recorder in a fresh macOS test account. The app runs on macOS 14 and later. Recording all 22 review clips requires macOS 15 or later. All the steps below run locally and require no cloud Mac subscription.

## What you are testing

The repository is `SamayPandey010726/skippy`. Use **main**. The application changes were merged at `a75abd1`. Commit `4a50b86` added the optional cloud recording workflow. The executable and bundle are named **Skippy**. The `ParcelApp` target, `ParcelCore` module, development bundle ID `com.yourcompany.parcel`, and storage folder `~/Library/Application Support/Parcel/` retain their earlier names for compatibility.

| Evidence at handoff | Scope |
| --- | --- |
| [Current portable test log](Artifacts/Skippy/Linux/swift-test.log) | 55 XCTest cases passed on Linux. Includes packaging, archive safety, persistence and quiver geometry. |
| [Parcels terminal recording](Artifacts/Skippy/Linux/Parcels-Linux-terminal.mp4) | 18 seconds at 1920 × 1080. The Linux engine creates a ZIP and compares extracted bytes with the original. |
| [Universal developer bundle](Artifacts/Skippy/Skippy-universal-developer.zip) | Cross-compiled from the merge for Intel and Apple silicon using the macOS 15.2 SDK. The binary slices and ad-hoc code and resource hashes were checked. Launch on a Mac and Gatekeeper acceptance are unverified for this bundle. Build from source below for local testing. |
| [Earlier Mac review](Artifacts/Skippy/Previous-Mac-4e52010/SKIPPY-TEST-RESULTS.md) | At `4e52010`, the predecessor with the horizontal floating strip passed 188 native tests and 89 running-app checks. Includes actual Mac footage, 18 tool screenshots and simulator startup images. |
| Native Mac verification | 191 XCTest cases passed. The universal app launched, the running-app checks passed for every arrow, and the menu-bar hover test followed the pointer into the shelf and back out. [Native test job](https://github.com/SamayPandey010726/skippy/actions/runs/44708012304/job/136192337597) |

## 1. Get the source and check the tools

In Terminal, clone the repository. If you already have a checkout, switch to `main` and use `git pull --ff-only` after saving any local work. Run the remaining commands from the repository root.

```bash
git clone https://github.com/SamayPandey010726/skippy.git
cd skippy
git rev-parse --short HEAD
sw_vers
uname -m
xcode-select -p
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
swift --version
```

Use the full Xcode application. The bundle script calls Xcode’s App Intents metadata processor. For recording, use Xcode 16 or newer with a macOS 15 or newer SDK. If the selected path ends in `CommandLineTools`, select the installed Xcode for this shell, for example `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Open Xcode once and finish first-launch setup if prompted. SwiftPM fetches the pinned ZIPFoundation dependency on the first build.

## 2. Test and build the native app

Run each command after the preceding command succeeds. The log files make it possible to report a failure without repeating a long run.

```bash
mkdir -p build/local-qa
set -o pipefail
swift test 2>&1 | tee build/local-qa/swift-test.log
bash Scripts/build-macos.sh 2>&1 | tee build/local-qa/build.log
bash Scripts/check-macos.sh 2>&1 | tee build/local-qa/smoke.log
codesign --verify --strict --verbose=2 build/Skippy.app
bash Scripts/apple-terminal.sh mac
```

On a Mac, SwiftPM includes both `ParcelCoreTests` and `ParcelAppTests`. Look for zero failures in the XCTest summary. The smoke script exercises the native image and licensing services, creates an archive with the real package builder and checks it with `unzip -t`. The bundle script produces an ad-hoc-signed `build/Skippy.app` for your Mac’s architecture. Its `--universal` option also builds the other architecture. Apple Developer ID signing and notarization remain release work.

## 3. Check the launcher by hand

On a fresh development install, look for the small floating Scout icon toward the upper right of the desktop. An existing install uses its saved position. Secondary-click the icon for **Settings…** and **Quit Skippy**. When testing the global shortcut, start with no file or text selected. With the relevant permissions, a selection can intentionally route straight into Parcels.

| Interaction | Expected observation |
| --- | --- |
| First launch and hover | The icon appears without a standalone workspace. Hover opens a wheel around a stationary center. File Shelf, Clipboard, Notes and Timer are the four default pins. |
| Preview, edit and fold | Keep TextEdit in front and hover an arrow. The preview should preserve TextEdit focus. Move into the preview, click the arrow to commit the tool, edit, and press Escape. Leaving both surfaces should fold the wheel. |
| Pins and More | In Settings, pin another arrow or Mac app. The first page holds up to six pins plus More. More cycles through the other tools in place. Clicking the center on a later page returns to the pins. A pinned external app launches when clicked. |
| Attachment | Drag the icon to the left and right edges. The bar should open vertically with the tool panel inside the display. Try the top, bottom, menu bar, notch and Dock placements from Settings. Verify the attachment survives relaunch. |
| Keyboard | Control–Option–Command–P summons Skippy. With Skippy active, Command–K opens search. Type `calc` and press Return. Option–Shift–B opens pinned-arrow navigation. Use arrows or Tab, Return and Escape to navigate. |
| Appearance and accessibility | From an active tool, Option–Shift–T switches light/dark and Option–Shift–I cycles the emblem. Check the corresponding choices in Settings. Rebind one action under Shortcuts, try it, then restore the default before automation. Also try Reduce Motion. |

For physical-device acceptance, try a real camera notch, an external monitor, Dock auto-hide and magnification, and dragging a file from the shelf into another app. The automated wheel film and layout tests cover only part of that behavior.

## 4. Record all 22 feature films

Use a **disposable, logged-in macOS user account** for this phase. The driver posts real mouse and keyboard events, activates TextEdit, replaces the system clipboard and the Skippy note, changes Skippy preferences and uses the account’s Downloads folder. Quit any existing Skippy instance, leave the primary display unlocked, use default pins and shortcuts, and let the driver control the desktop until it finishes. Use sample data. A recording captures whatever is visible in its screen region.

In **System Settings → Privacy & Security**, grant Accessibility and Screen Recording to the relevant Terminal or helper identified by macOS. Recent macOS versions label screen recording **Screen & System Audio Recording**. Relaunch the affected process after changing permissions. A Files and Folders prompt can appear for Downloads. The Calendar automation expects the initial **Connect** control. Test populated calendars and third-party media accounts separately.

The capture and export steps use `python3`, `ffmpeg` and `ffprobe`. If you use Homebrew, `brew install ffmpeg` provides the last two. In the test account’s checkout, run:

```bash
command -v python3 ffmpeg ffprobe
mkdir -p build/local-qa
set -o pipefail
bash Scripts/record-feature-library.sh 2>&1 | tee build/local-qa/recording.log
```

The script builds its own app and helpers and prints the path to **Review/index.html** on success. Open that exact file. Each invocation uses a new `build/feature-review.XXXXXX/` directory.

| Output inside the run directory | Contents |
| --- | --- |
| `Review/index.html` | Offline gallery with individual playback and download links. |
| `Review/*.mp4` and `Review/*.jpg` | 22 separate 1920 × 1080 videos, 15–20 seconds each, and their posters. The exporter checks dimensions and duration. Visually check framing, cursor motion, readability and the observed result. |
| `Review/Floating-wheel.gif` | Animated launcher preview. |
| `build/feature-captures/<title>/WindowServer.mp4` | Raw ScreenCaptureKit recordings for individual features, including completed captures from a partially failed run. |
| `build/recordings/Arrows/` and `build/Skippy.log` | Per-arrow stills and the app’s diagnostic output. |

**Feature coverage.** Three films cover the floating wheel, keyboard/themes, and Settings. The remaining 19 cover File Shelf, Clipboard, Extract text, Pick colour, Timer, Notes, QR generator, QR scanner, Search, Apps, Music, Downloads, Stay awake, Recent actions, Mac, Calendar, Calculator, Screenshots and Draw on screen. QR generation and scanning are two recordings of the same arrow. Clips are silent. Real-time motion should be judged live as well because the exporter can shorten a long interaction for review.

**Functional spot checks.** Paste a file into File Shelf, drag it out to Finder and compare its contents. Type a unique QR payload, copy the image, select Scan clipboard and compare the decoded text exactly. In Calculator, `(24 + 8) / 2` should copy `16`. Capture two screen regions and inspect the combined image. Start a drawing, draw one stroke, undo it and close the overlay. Search’s automated check exercises query editing. Calendar checks the consent entry point on a fresh account. Check browser launch, actual Calendar events and audible playback manually. The per-tool matrix lists the remaining checks. [Interaction QA](Docs/SKIPPY-INTERACTION-QA.md)

## 5. Diagnose a local failure

| Symptom | What to check |
| --- | --- |
| Command-line build fails at App Intents or SDK lookup | Compare the selected Xcode and SDK from step 1. Read the first compiler or metadata-processor error in `build/local-qa/build.log`. |
| The wheel is missing, opens at a different edge or has unexpected pins | Check for another running copy with `pgrep -x Skippy`. Quit it through its menu. Verify the saved attachment under Everyday, the primary display and the pins in the test account. |
| Keystrokes land in another app, no preview appears, or the capture is blank | Check Accessibility and Screen Recording in the active test user. Close unrelated foreground windows or permission sheets and retry with the display awake. The keyboard test also assumes the default global shortcut is available. |
| Recording stops at Downloads on a repeat run | The driver creates `~/Downloads/Skippy QA.txt` with overwrite protection. An interrupted run can leave it behind. Inspect it first. If it is the generated fixture, move it aside before retrying. |
| One feature fails and no review index appears | Find the first `FAIL` or thrown error in `build/local-qa/recording.log`. Keep the run directory. Check the raw clip, its still and `build/Skippy.log`. Packaging starts after the driver completes successfully. |
| Only one permission-dependent integration fails | Record the exact action and permission state. Dock hover uses Accessibility. Calendar reads need Calendar access. Controlling Music or Spotify may trigger Automation consent. Local playback is a separate test. |

For a bug report, include the commit from `git rev-parse HEAD`, macOS/Xcode versions, Mac model, display arrangement and scaling, attachment, active theme, shortcut changes, reproduction steps, expected result, actual result, and the relevant log or clip timestamp. Check captured screens for personal content before sharing.

## Implementation map and next milestone

| Area | Start here |
| --- | --- |
| Launcher geometry and interaction | [QuiverGeometry.swift](Sources/ParcelCore/QuiverGeometry.swift) calculates the frame and hit targets. [SkippyQuiver.swift](Sources/ParcelApp/Services/SkippyQuiver.swift) handles hover, focus, paging and placement. |
| Windows, Settings and shortcuts | [AppController.swift](Sources/ParcelApp/Services/AppController.swift), [DropPopup.swift](Sources/ParcelApp/Services/DropPopup.swift), [PreferencesView.swift](Sources/ParcelApp/Views/PreferencesView.swift) and [CourierKeyboardShortcuts.swift](Sources/ParcelApp/Services/CourierKeyboardShortcuts.swift). |
| Tools and file packing | [NotchTools.swift](Sources/ParcelApp/Services/NotchTools.swift) implements the tool panels and their actions. [NotchWidgets.swift](Sources/ParcelApp/Services/NotchWidgets.swift) stores layout and pins. [PackageBuilder.swift](Sources/ParcelCore/PackageBuilder.swift) creates the ZIP. |
| Native tests and films | [Mac smoke script](Scripts/check-macos.sh), [Quartz and Accessibility driver](Scripts/check-arrow-navigation.swift), [recording entry point](Scripts/record-feature-library.sh) and [video exporter](Scripts/package-feature-films.py). |

iPhone, iPad and cross-device Parcels sync remain planned. The simulator helper can boot devices, but there is no mobile application target yet. The roadmap covers private CloudKit storage, explicit file and clipboard intake, and handoff through the system share sheet or supported drag destinations. [Feature brief and mobile roadmap](SKIPPY-BRIEF.md) · [Implementation plan](Docs/SKIPPY-PLAN.md)
