# CaptureArc Mac App Store readiness

Status: **Ready for owner-approved review submission**

The app, App Store record, free pricing, listing, public support pages, privacy disclosure, worldwide availability, review contact, and distribution-signed installer are prepared. Apple processed build 1.0.0 (2) successfully, and it is attached to macOS version 1.0. App Store Connect enables **Add for Review** with no unresolved validation blocker.

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
- **Data Not Collected** privacy disclosure published
- Availability enabled for all 175 countries and regions
- App Review contact name, phone, and email saved
- Manual release selected
- Transporter installed and signed package delivered
- Build 1.0.0 (2) completed Apple processing and was attached to version 1.0
- Final version draft saved with **Add for Review** enabled

## Remaining human release gate

1. Optionally install build 2 through TestFlight for a second-Mac/user smoke test.
2. The owner manually approves **Add for Review**.
3. Inspect the generated review submission, then the owner manually approves **Submit for Review**.

## Distribution build commands

Local sandbox QA candidate:

```bash
./script/build_app_store.sh --verify --run
```

Rebuild the final installer with the matching profile:

```bash
APP_STORE_BUILD_NUMBER="<next-unused-build-number>" \
  APP_STORE_PROVISIONING_PROFILE="/absolute/path/CaptureArc_AppStore.provisionprofile" \
  ./script/build_app_store.sh --package
```

For non-default or temporary signing keychains, also set `APP_STORE_SIGNING_KEYCHAIN` to the keychain path.

The packaging command intentionally fails if any required distribution asset is missing or does not match the bundle ID. It also strips inherited quarantine metadata before signing because App Store processing rejects that extended attribute anywhere in the package payload.
