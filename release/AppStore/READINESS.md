# CaptureArc Mac App Store readiness

Status: **Blocked before App Store Connect record creation**

The app itself is prepared as a sandboxed Mac App Store candidate. The remaining blockers are account/legal, distribution signing, public URLs, and owner decisions.

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

## Blocking account work

1. The Account Holder must accept the updated Apple Developer Program License Agreement.
2. Complete Digital Services Act trader-status compliance for EU distribution, using the owner's accurate legal/business status.
3. Update legal-entity information and accept the Paid Apps Agreement only if the app will be paid or use in-app purchases.
4. Register the explicit App ID `com.illiagryniuk.capturearc`.
5. Create/download an Apple Distribution certificate, a Mac Installer Distribution certificate, and a Mac App Store provisioning profile.
6. Reserve the final app name in App Store Connect. Public search found no exact CaptureArc listing, but only record creation confirms availability.

## Blocking publishing work

1. Confirm price, territories, release mode, support ownership, and App Review contact.
2. Build the installer package with the distribution identities and provisioning profile.
3. Upload the build, complete the App Store forms, and run an internal/TestFlight check.
4. Manually approve **Add for Review** and **Submit for Review**.

## Distribution build commands

Local sandbox QA candidate:

```bash
./script/build_app_store.sh --verify --run
```

Final installer after certificates/profile exist:

```bash
APP_STORE_PROVISIONING_PROFILE="/absolute/path/CaptureArc_AppStore.provisionprofile" \
  ./script/build_app_store.sh --package
```

The packaging command intentionally fails if any required distribution asset is missing or does not match the bundle ID.
