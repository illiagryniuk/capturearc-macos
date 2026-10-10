# CaptureArc Mac App Store readiness

Status: **Ready for owner hands-on QA; upload held for approval**

The updated app, free App Store record, listing copy, support/privacy drafts, and distribution-signed installer are prepared. Apple previously processed build 1.0.0 (2), but that build is now superseded by the local build 1.0.0 (3), which contains exact-notch activation and the new persistent Files shelf. Build 3 is intentionally not uploaded until owner testing and explicit release approval.

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
- Exact physical-notch activation with the surrounding collapsed panel ignoring mouse events
- Larger 820×540 shelf with Screenshots and Files sections
- Multiple persistent folder tabs, Finder-style browsing, nested navigation, default-app opening, and Finder reveal
- Local bookmark persistence and restoration test coverage
- Visual inspection of the Files workspace and native folder picker in both local and App Sandbox configurations
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

## Remaining release work

1. Owner tests the running local build, especially exact-notch activation and real folder tabs.
2. Refresh at least one App Store screenshot to show the new Files section.
3. Upload build 1.0.0 (3), wait for Apple processing, and attach it to macOS version 1.0.
4. Optionally install build 3 through TestFlight for a second-Mac/user smoke test.
5. The owner manually approves **Add for Review** and **Submit for Review**.

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
