# CaptureArc Mac App Store readiness

Status: **Prepared for final App Store Connect completion**

The app, App Store record, free pricing, listing draft, public support pages, and distribution-signed installer are prepared. Four owner-confirmed actions remain before build upload and review: publish the privacy disclosure, choose availability territories, use the owner's contact details for App Review, and install/use Apple's Transporter uploader.

## Completed locally

- Working brand and unique store-facing name: CaptureArc
- 1024 px App Store icon plus complete `.icns` icon set
- Sandboxed App Store build path
- User-selected read/write folder entitlement
- App-scoped security bookmark that survives relaunch
- No broad file, Screen Recording, Accessibility, or Full Disk Access entitlement
- Privacy manifest with required-reason API declarations
- Export-compliance key set in Info.plist
- Version 1.0 metadata, review notes, privacy questionnaire, and public privacy, support, and Terms pages
- Mac App Store screenshot source captures and generator
- Release build and strict code-signature verification
- Universal Apple silicon + Intel release binary
- Automated test suite
- Live sandbox test: authorize folder, detect a new screenshot, show it in the shelf, relaunch, and restore access
- Apple Developer Program agreement accepted and Digital Services Act status active
- Free Apps Agreement active; no paid agreement is required while CaptureArc remains free and has no in-app purchases
- Explicit App ID registered: `com.illiagryniuk.capturearc`
- App Store Connect record created: `CaptureArc: Screenshot Shelf` (Apple ID `6789554439`)
- Apple-issued Mac App Distribution and Mac Installer Distribution certificates installed
- Mac App Store provisioning profile created and matched to the app and team
- Distribution-signed universal app and installer package created
- Version 1.0 listing, categories, age rating, content rights, review notes, and public URLs saved
- Five 2880x1800 screenshots uploaded and ordered from `01` through `05`
- Price set to USD 0.00 across all 175 price regions
- App privacy answer saved as **Data Not Collected**
- Manual release selected

## Remaining owner-confirmed actions

1. Publish the saved **Data Not Collected** privacy disclosure.
2. Choose App Availability territories (recommended: all available countries and regions).
3. Authorize use of the owner's existing Apple account contact details for the App Review contact fields.
4. Authorize installation of Apple's Transporter app and upload `dist/AppStore/CaptureArc-1.0.0.pkg`.

## Work after those confirmations

1. Wait for Apple's build processing and select build 1.0.0 (1) on the version page.
2. Resolve any App Store Connect validation messages and run an internal/TestFlight check if available.
3. The owner manually approves **Add for Review** and **Submit for Review**.

## Distribution build commands

Local sandbox QA candidate:

```bash
./script/build_app_store.sh --verify --run
```

Rebuild the final installer with the matching profile:

```bash
APP_STORE_PROVISIONING_PROFILE="/absolute/path/CaptureArc_AppStore.provisionprofile" \
  ./script/build_app_store.sh --package
```

For non-default or temporary signing keychains, also set `APP_STORE_SIGNING_KEYCHAIN` to the keychain path.

The packaging command intentionally fails if any required distribution asset is missing or does not match the bundle ID.
