# Developer deployment handoff

## First build

Use macOS 14+ and a current Xcode with a selected toolchain. Swift language mode is 5, allowing the project to compile with Swift 6 without turning the entire app into a strict-concurrency migration. The minimum package tools version is 5.9.

```bash
cd Parcel
swift test
bash Scripts/build-macos.sh
bash Scripts/check-macos.sh
open build/Parcel.app
```

The first script builds and bundles the native executable, resources, icon and Info.plist. Its default is an ad-hoc signed developer build with licensing disabled. **Do not sell/distribute that developer build as the production app.** Run the native acceptance matrix, fix SDK/type/runtime errors if any, and record the results. This Linux handoff could not complete that stage.

`Package.swift` is the project entry point; a handwritten `.xcodeproj` is not required. The app/resource bundle is assembled by the script because a SwiftPM executable on its own is not a complete distributable app. The resource locator supports both SwiftPM development and resources inside the assembled app.

## Brand and repository

Parcel is a working title; an existing Mac delivery-tracking app uses that name. Select the public release name before launch. Update the brand mark/window labels and Info.plist consistently, and set your real reverse-DNS bundle identifier. Keep the internal licence product slug stable unless both verifier and issuer are changed together.

The source can be put in a GitHub repository named `MacOS`, as requested earlier. Initialise it under the developer's account and enable `.github/workflows/check.yml`. That workflow compiles, tests, bundles and runs the native service smoke checks on macOS. The build artifact is wrapped in a ZIP to preserve executable permissions. It is a review build, not a signed commercial release.

## Merchant licence key

The private key stays outside the repository, app bundle, download archive and public hosting. Install `cryptography` only in the merchant/developer Python environment; users need no Python.

```bash
python3 -m pip install cryptography
mkdir -p "$HOME/.config/parcel"
python3 Scripts/license-tool.py keygen \
  --private "$HOME/.config/parcel/merchant.private"
```

The command prints the public key in ordinary base64. Copy that value into `PARCEL_LICENSE_PUBLIC_KEY`; never put the private file in the app. Key generation refuses to overwrite an existing key. Back up the private key securely: losing it prevents issuance of compatible future licences.

After a verified paid order:

```bash
python3 Scripts/license-tool.py issue \
  --private "$HOME/.config/parcel/merchant.private" \
  --customer "Customer name" \
  --license-id "your-provider-order-id" \
  --plan two \
  --machine-id "PASTE_CUSTOMER_MAC_ID" > customer-licence.txt
```

Deliver the complete token from that file to the buyer. They paste it into Parcel → Preferences → Your licence. The token is verified offline with CryptoKit and stored in Keychain. Default tokens are perpetual; `--expiry` exists for controlled test/support use.

**Machine-locked keys.** Ask the buyer for each Mac ID from Parcel → Preferences → Your licence → "This Mac's ID". Choose `--plan single`, `two` or `five`, and repeat `--machine-id` for every authorised Mac. The issuer rejects missing IDs, duplicates and counts above the purchased plan.

No merchant fulfilment service has been deployed. A manual early launch can issue keys after verified orders. For automation, call the same issuance function from a merchant-side handler only after verifying the payment provider's webhook signature, product and paid status, then make issuance idempotent using the provider order ID. Delivery/receipt configuration belongs to the chosen merchant platform. Do not trust a browser success redirect as proof of payment.

Machine-locking is enforced offline by the app. Each signed key names its one-, two- or five-Mac plan and the allowed Mac IDs. There is no activation server counting installs; adding a Mac requires the merchant to reissue the key with the new ID while staying within the purchased limit.

## App Store distribution

The current build uses the same signed licence gate on every distribution channel. It deliberately does not trust receipt-file presence as purchase proof. Build the App Store package with:

```bash
export PARCEL_BUNDLE_ID="com.yourcompany.yourproduct"
export PARCEL_LICENSE_PUBLIC_KEY="BASE64_PUBLIC_KEY_FROM_KEYGEN"
export PARCEL_CHECKOUT_URL="https://your-real-checkout-url"
bash Scripts/build-macos.sh --appstore
```

This turns off development mode and embeds the same public verification key used by direct downloads. Final submission goes through Xcode (Product → Archive) with your Apple Distribution certificate and App Store provisioning profile, and the App Sandbox entitlement must be enabled before review — the bundled `Config/Parcel.entitlements` targets direct Developer ID distribution with sandbox disabled, so do not submit that configuration unchanged.

## Production bundle

Use your real checkout URL and Developer ID Application identity from Keychain. The public key is not a secret. Signing/notarization credentials are.

```bash
export PARCEL_BUNDLE_ID="com.yourcompany.yourproduct"
export PARCEL_LICENSE_PUBLIC_KEY="BASE64_PUBLIC_KEY_FROM_KEYGEN"
export PARCEL_CHECKOUT_URL="https://your-real-checkout-url"
export PARCEL_SIGN_IDENTITY="Developer ID Application: Your Company (TEAMID)"
export PARCEL_VERSION="1.0.0"
export PARCEL_BUILD_NUMBER="1"
bash Scripts/build-macos.sh --production --universal
```

The production switch refuses missing/placeholder configuration or ad-hoc signing. `--universal` builds arm64 and x86_64 separately and combines them with `lipo`. Omit it for a platform-specific review build. Review warnings, the privacy manifest and the bundled third-party acknowledgements.

The entitlement file intentionally targets direct Developer ID distribution, with sandbox disabled. The UI still operates on explicitly selected content and saved bookmarks. There is no Full Disk Access or Screen Recording request. App Store distribution would need a separate sandbox/entitlement/review pass rather than republishing this direct-download configuration unchanged.

## Notarization and download artifacts

Store Apple credentials in the developer's Keychain using `xcrun notarytool store-credentials`. Do not commit credentials or app-specific passwords. Choose a profile name, then:

```bash
export PARCEL_NOTARY_PROFILE="YOUR_STORED_KEYCHAIN_PROFILE"
bash Scripts/notarize-macos.sh
```

This submits the production app archive, waits for acceptance, staples the ticket, validates it, runs Gatekeeper assessment and produces `build/Parcel-macOS.zip` and `build/Parcel.dmg`. The DMG includes an Applications shortcut. The script prints SHA-256 hashes. No upload to a public download host is performed automatically.

Install the notarized app on a clean second Mac from the hosted artifact. Check Gatekeeper, resource lookup, icon, the locked activation screen, valid and invalid licences, floating hotkey, dragging, image preparation, AirDrop and sharing. Test both Apple Silicon and Intel if claiming support for both. Keep the app out of an App Translocation location by installing into Applications for final checks.

## Launch operations

Host the notarized artifacts, connect the $2.49 / $4.99 / $9.99 products to the checkout link and deliver the matching one-, two- or five-Mac licence. Supply clear install/activation instructions and a support address. Verify one real paid-and-refunded test order through the chosen provider before public launch; do not infer payment readiness from the app opening a URL.

This source does not include an automatic updater. Initial updates are signed/notarized replacements distributed through your download page. A future Sparkle integration requires feed hosting, signatures, update entitlement decisions and its own acceptance checks.

Retain tagged source and hashes for each shipped version. Re-run core tests, native smoke checks and changed acceptance scenarios for every release. Report actual native memory/energy measurements rather than promoting estimated figures from this handoff.
