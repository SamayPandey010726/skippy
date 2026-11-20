#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Notarization requires macOS.' >&2;exit 1; }
: "${PARCEL_NOTARY_PROFILE:?Set the Keychain profile previously stored with xcrun notarytool store-credentials}"
app='build/Skippy.app'
[[ -d "$app" ]] || { echo 'Build the production app first.' >&2;exit 1; }
mode="$(/usr/libexec/PlistBuddy -c 'Print :ParcelDevelopmentMode' "$app/Contents/Info.plist")"
[[ "$mode" == false ]] || { echo 'Refusing to notarize a developer-mode app.' >&2;exit 1; }
codesign --verify --strict --verbose=2 "$app"
ditto -c -k --keepParent "$app" build/Skippy-notary.zip
xcrun notarytool submit build/Skippy-notary.zip --keychain-profile "$PARCEL_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --keepParent "$app" build/Skippy-macOS.zip
staging="$(mktemp -d "${TMPDIR:-/tmp}/Parcel-dmg.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
cp -R "$app" "$staging/Skippy.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Skippy -srcfolder "$staging" -ov -format UDZO build/Skippy.dmg
shasum -a 256 build/Skippy-macOS.zip build/Skippy.dmg
echo 'Notarized artifacts are ready for your download host.'
