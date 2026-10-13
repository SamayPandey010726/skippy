#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Native smoke checks require macOS.' >&2;exit 1; }
swift build --product Parcel
swift build --product ParcelCheck
bin="$(swift build --show-bin-path)"
objects=()
for file in "$bin"/ParcelCore.build/*.o "$bin"/ZIPFoundation.build/*.o; do
    [[ ! -f "$file" ]] || objects+=("$file")
done
# Compile the actual native service source with a dedicated @main, without launching the GUI.
xcrun swiftc -swift-version 5 -parse-as-library -I "$bin/Modules" \
    Sources/ParcelApp/Services/StoragePaths.swift Sources/ParcelApp/Services/ImagePipeline.swift \
    Sources/ParcelApp/Services/LicenseManager.swift Scripts/MacSmoke.swift \
    "${objects[@]}" -o "$bin/ParcelMacSmoke"
"$bin/ParcelMacSmoke"
root="$(mktemp -d "${TMPDIR:-/tmp}/Parcel-check.XXXXXX")"
trap 'rm -rf -- "$root"' EXIT
"$bin/ParcelCheck" "$root/package"
unzip -t "$root/package/Parcel.zip"
