#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Select a Mac with Xcode to run this command.' >&2; exit 1; }
case "${1:-mac}" in
  mac)
    [[ -x build/Skippy.app/Contents/MacOS/Skippy ]] || bash Scripts/build-macos.sh
    open build/Skippy.app
    ;;
  iphone|ipad)
    family=iPhone
    [[ "$1" == iphone ]] || family=iPad
    id="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
ios = [key for key in devices if ".iOS-" in key]
for key in sorted(ios, key=lambda k: tuple(map(int, k.split(".iOS-")[-1].split("-"))), reverse=True):
    matches = [d for d in devices[key] if d["name"].startswith(sys.argv[1]) and d["isAvailable"]]
    if matches:
        print(next((d for d in matches if d["state"] == "Booted"), matches[0])["udid"])
        break
' "$family")"
    [[ -n "$id" ]] || { echo "No available $family simulator runtime." >&2; exit 1; }
    xcrun simctl bootstatus "$id" -b
    if [[ -n "${SKIPPY_SIM_CAPTURE:-}" ]]; then
      xcrun simctl io "$id" screenshot "$SKIPPY_SIM_CAPTURE"
    else
      open -a Simulator --args -CurrentDeviceUDID "$id"
    fi
    echo "$family simulator ready: $id"
    ;;
  *) echo 'Usage: Scripts/apple-terminal.sh mac|iphone|ipad' >&2; exit 2 ;;
esac
