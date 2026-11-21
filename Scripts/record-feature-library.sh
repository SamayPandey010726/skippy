#!/bin/bash
# Run in a disposable, logged-in macOS test account with Accessibility and Screen Recording enabled.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null
if [[ "${SKIPPY_REUSE_BUILD:-false}" == true ]]; then
  test -x build/Skippy.app/Contents/MacOS/Skippy
elif [[ "${SKIPPY_UNIVERSAL:-false}" == true ]]; then
  bash Scripts/build-macos.sh --universal
else
  bash Scripts/build-macos.sh
fi
run_dir="$(mktemp -d "$PWD/build/feature-review.XXXXXX")"
mkdir -p "$run_dir/build/recordings" "$run_dir/Review"
ln -s "$PWD/Samples" "$run_dir/Samples"
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" Scripts/record-display.swift -o "$run_dir/build/display-recorder"
swiftc -target "$(uname -m)-apple-macos14.0" Scripts/record-quiver.swift -o "$run_dir/build/record-quiver"
swiftc -target "$(uname -m)-apple-macos14.0" Scripts/check-arrow-navigation.swift -o "$run_dir/build/check-arrows"
app_path="$PWD/build/Skippy.app"
renderer="$PWD/Scripts/package-feature-films.py"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"
defaults write "$bundle_id" skippy.surface -string Floating
defaults write "$bundle_id" skippy.x -float 0.52
defaults write "$bundle_id" skippy.y -float 0.78
defaults write "$bundle_id" parcel.idleTimeout -float 0
defaults write "$bundle_id" parcel-skin -string night
if [[ "${SKIPPY_FILM_BATCH:-all}" == workspace || "${SKIPPY_FILM_BATCH:-all}" == settings-review ]]; then
  pin_data="$(python3 -c 'import json; print(json.dumps([{"id": "calculator", "position": 2, "alwaysVisible": True}, {"id": "music", "position": 0, "alwaysVisible": False}]).encode().hex())')"
  defaults write "$bundle_id" skippy.quickPins -data "$pin_data"
fi
cd "$run_dir"
"$app_path/Contents/MacOS/Skippy" >build/Skippy.log 2>&1 &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true' EXIT
sleep 2
open -a "$app_path" "$PWD/Samples/Launch notes.txt" "$PWD/Samples/A little place.png"
sleep 2
batch="${SKIPPY_FILM_BATCH:-all}"
if [[ "$batch" == all || "$batch" == wheel ]]; then
  build/record-quiver "build/feature-captures/Floating wheel" "$app_pid"
fi
if [[ "$batch" != wheel ]]; then
  SKIPPY_FEATURE_FILMS=1 build/check-arrows "$app_pid"
fi
if [[ "$batch" != all ]]; then exit 0; fi
python3 "$renderer" build/feature-captures Review
echo "Feature library: $PWD/Review/index.html"
