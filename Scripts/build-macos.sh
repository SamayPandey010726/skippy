#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then echo 'This bundle build requires macOS and Xcode.' >&2; exit 1; fi
production=false
universal=false
appstore=false
for flag in "$@"; do
    case "$flag" in --production) production=true ;; --universal) universal=true ;; --appstore) appstore=true ;; *) echo "Unknown option: $flag" >&2;exit 2 ;; esac
done
xcode-select -p >/dev/null
bundle_id="${PARCEL_BUNDLE_ID:-com.yourcompany.parcel}"
version="${PARCEL_VERSION:-1.0.0}"
build_number="${PARCEL_BUILD_NUMBER:-1}"
identity="${PARCEL_SIGN_IDENTITY:--}"
if $production || $appstore; then
    [[ "$bundle_id" != com.yourcompany.parcel ]] || { echo 'Set PARCEL_BUNDLE_ID to your identifier.' >&2;exit 1; }
    [[ -n "${PARCEL_LICENSE_PUBLIC_KEY:-}" && -n "${PARCEL_CHECKOUT_URL:-}" ]] || { echo 'Production needs a licence public key and HTTPS checkout URL.' >&2;exit 1; }
    python3 - <<'PY'
import base64,os,urllib.parse
key=base64.b64decode(os.environ['PARCEL_LICENSE_PUBLIC_KEY'],validate=True)
assert len(key)==32,'The Ed25519 public key must be 32 bytes.'
u=urllib.parse.urlparse(os.environ['PARCEL_CHECKOUT_URL']);assert u.scheme=='https' and u.netloc,'Use an HTTPS checkout URL.'
PY
fi
if $production; then
    [[ "$identity" != - ]] || { echo 'Production needs PARCEL_SIGN_IDENTITY (Developer ID Application).' >&2;exit 1; }
fi
if $appstore; then
    [[ "$bundle_id" != com.yourcompany.parcel ]] || { echo 'Set PARCEL_BUNDLE_ID to your App Store identifier.' >&2;exit 1; }
fi
mkdir -p build
architectures=("$(uname -m)")
if $universal; then architectures=(arm64 x86_64); fi
binaries=()
resource_bin=''
swift_options=()
if [[ "${PARCEL_SWIFT_DISABLE_SANDBOX:-0}" == 1 ]]; then swift_options+=(--disable-sandbox); fi
if [[ -n "${PARCEL_SWIFT_DEBUG_INFO:-}" ]]; then swift_options+=(-debug-info-format "$PARCEL_SWIFT_DEBUG_INFO"); fi
# SwiftPM's native build system needs explicit constant extraction for App Intents.
intent_staging="$(mktemp -d "${TMPDIR:-/tmp}/Skippy-intents.XXXXXX")"
trap 'rm -rf -- "$intent_staging"' EXIT
echo '["AppIntent","AppEntity","AppEnum","AppShortcutsProvider","EntityQuery","DynamicOptionsProvider"]' > "$intent_staging/protocols.json"
for arch in "${architectures[@]}"; do
    scratch=".build/bundle-$arch"
    swift build ${swift_options[@]+"${swift_options[@]}"} --scratch-path "$scratch" -c release --product Skippy --arch "$arch" \
      -Xswiftc -emit-const-values -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file \
      -Xswiftc -Xfrontend -Xswiftc "$intent_staging/protocols.json"
    bin="$(swift build ${swift_options[@]+"${swift_options[@]}"} --scratch-path "$scratch" -c release --arch "$arch" --show-bin-path)"
    binaries+=("$bin/Skippy")
    resource_bin="$bin"
done
app='build/Skippy.app'
if [[ -e "$app" ]]; then rm -rf -- "$app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if $universal; then lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Skippy"; else cp "${binaries[0]}" "$app/Contents/MacOS/Skippy"; fi
cp Config/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$app/Contents/Info.plist"
if $production || $appstore; then
    plutil -replace ParcelDevelopmentMode -bool NO "$app/Contents/Info.plist"
fi
if $production || $appstore; then
    plutil -replace ParcelLicensePublicKey -string "$PARCEL_LICENSE_PUBLIC_KEY" "$app/Contents/Info.plist"
    plutil -replace ParcelCheckoutURL -string "$PARCEL_CHECKOUT_URL" "$app/Contents/Info.plist"
fi
for resource in "$resource_bin"/*.bundle; do
    [[ ! -d "$resource" ]] || cp -R "$resource" "$app/Contents/Resources/"
done
cp Sources/ParcelApp/Resources/PrivacyInfo.xcprivacy "$app/Contents/Resources/"
cp Sources/ParcelApp/Resources/Acknowledgements.txt "$app/Contents/Resources/"
cp Sources/ParcelApp/Resources/paper-seal.wav "$app/Contents/Resources/"

# SwiftPM compiles App Intents but does not package their discoverability
# metadata into a hand-assembled .app. Mirror Xcode's metadata extraction so
# Shortcuts, Siri and Spotlight can discover Parcel's actions after install.
primary_arch="${architectures[0]}"
intent_sources="$intent_staging/sources.txt"
find "$PWD/Sources/ParcelApp" -type f -name '*.swift' | sort > "$intent_sources"
find "$PWD/.build/bundle-$primary_arch" -type f -name '*.swiftconstvalues' -path '*/ParcelApp.build/*' > "$intent_staging/const-values.txt"
if [[ -s "$intent_staging/const-values.txt" ]]; then
    xcrun appintentsmetadataprocessor \
        --output "$intent_staging" \
        --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
        --module-name ParcelApp \
        --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
        --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
        --platform-family macOS \
        --deployment-target 14.0 \
        --target-triple "$primary_arch-apple-macos14.0" \
        --source-file-list "$intent_sources" \
        --swift-const-vals-list "$intent_staging/const-values.txt" \
        --force
    if [[ -d "$intent_staging/Metadata.appintents" ]]; then
        cp -R "$intent_staging/Metadata.appintents" "$app/Contents/Resources/"
    elif $production || $appstore; then
        echo 'App Intents metadata extraction produced no output; refusing the distribution build.' >&2
        exit 1
    else
        echo 'App Intents metadata was not emitted for this local development build.' >&2
    fi
    rm -rf -- "$intent_staging"
else
    echo 'Missing App Intents compiler metadata; refusing to ship undiscoverable shortcuts.' >&2
    exit 1
fi
if ! iconutil -c icns Assets/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"; then
    python3 Scripts/pack-icon.py Assets/AppIcon.iconset "$app/Contents/Resources/AppIcon.icns"
fi
if $production; then
    # Resources contain no nested executable frameworks. ZIPFoundation is linked statically.
    codesign --force --options runtime --timestamp --sign "$identity" --entitlements Config/Parcel.entitlements "$app"
else
    codesign --force --sign - "$app"
fi
if $appstore; then
    echo 'App Store note: submit through Xcode (Product > Archive) with your Apple Distribution certificate'
    echo 'and App Store provisioning profile, and enable the App Sandbox entitlement before review.'
fi
codesign --verify --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist"
echo "Built $app"
echo 'Run Scripts/check-macos.sh and the Mac acceptance checklist before distribution.'
