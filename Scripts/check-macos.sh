#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Native smoke checks require macOS.' >&2;exit 1; }
swift_options=()
if [[ "${PARCEL_SWIFT_DISABLE_SANDBOX:-0}" == 1 ]]; then swift_options+=(--disable-sandbox); fi
swift build ${swift_options[@]+"${swift_options[@]}"} --product Parcel
swift build ${swift_options[@]+"${swift_options[@]}"} --product ParcelCheck
bin="$(swift build ${swift_options[@]+"${swift_options[@]}"} --show-bin-path)"
objects=()
module_path="$bin/Modules"
if [[ -f "$bin/ParcelCore.o" ]]; then
    module_path="$bin"
    objects+=("$bin/ParcelCore.o" "$bin/ZIPFoundation.o")
else
    for file in "$bin"/ParcelCore.build/*.o "$bin"/ZIPFoundation.build/*.o; do
        [[ ! -f "$file" ]] || objects+=("$file")
    done
fi
# Compile the actual native service source with a dedicated @main, without launching the GUI.
xcrun swiftc -swift-version 5 -D PARCEL_TESTING -parse-as-library -I "$module_path" \
    Sources/ParcelApp/Services/StoragePaths.swift Sources/ParcelApp/Services/ImagePipeline.swift \
    Sources/ParcelApp/Services/LicenseManager.swift Scripts/MacSmoke.swift \
    "${objects[@]}" -o "$bin/ParcelMacSmoke"
"$bin/ParcelMacSmoke"
root="$(mktemp -d "${TMPDIR:-/tmp}/Parcel-check.XXXXXX")"
trap 'rm -rf -- "$root"' EXIT
"$bin/ParcelCheck" "$root/package"
unzip -t "$root/package/Parcel.zip"
