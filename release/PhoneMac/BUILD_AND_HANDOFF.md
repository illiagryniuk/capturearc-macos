# Build and handoff

**Current store handoff:** See [STORE_STATUS.md](STORE_STATUS.md). The iPhone 1.0 (1) upload succeeded and must not be repeated. Both records now exist. The owner has authorized App Review submission of both apps, with public release remaining manual.

## Source
Isolated branch `codex/capturearc-phone-mac-release-prep`, based on remote main `51f0be8ff58a39e3d3e45f8fda8d93af3552c3b9`. Integrates the locally tested Share/ACK/AutoCopy/Cards demo without modifying the original production checkout. No changes were pushed or merged.

## Mac update
Version 1.2 (4), bundle `com.illiagryniuk.capturearc`, same identity as the existing Mac app. Universal arm64/x86_64, macOS 13+.

```sh
APP_STORE_PROVISIONING_PROFILE='/path/to/CaptureArc.provisionprofile' \
APP_STORE_MARKETING_VERSION=1.2 APP_STORE_BUILD_NUMBER=4 \
bash script/build_app_store.sh --package
```

Uses existing valid Mac App Store application and installer certificates. Output: `dist/AppStore/CaptureArc-1.2.pkg`. This is an App Store upload installer, not a public Developer ID download. It is deliberately not notarized: App Store distribution uses Apple's review/signing path. The local QA copy has a separate bundle ID and is not the shipping artifact.

For the November 22 upload, the unchanged signed app was copied into an isolated `artifacts/Mac-Release/CaptureArc.xcarchive` with archive metadata recording its actual bundle/version/build and universal architectures. Xcode then successfully exported it using `Mac-AppStore-Export.plist`. The existing provisioning profile is Xcode-managed, so export uses automatic signing with the existing Mac application/installer identities. No certificate was revoked and no security entitlement was added. The exported app's Info.plist and embedded profile are byte-identical to the original; arm64/x86_64 executable code/data segments match. Xcode refreshed the code signature, so the container/package hash differs.

```sh
xcodebuild -exportArchive -archivePath /path/to/CaptureArc.xcarchive \
  -exportPath /path/to/Mac-AppStore-export \
  -exportOptionsPlist release/PhoneMac/Mac-AppStore-Export.plist \
  -allowProvisioningUpdates
```

`Mac-AppStore-Upload.plist` selects `destination=upload`. Use it only after checking the exact version/build is not already delivered. Mac 1.2 (4) has now uploaded successfully from the corrected `Mac-Release-ResourceID` archive. The first attempt exposed a missing SwiftPM resource bundle identifier; the packaging script now adds it before signing. The local Mac PKG was rebuilt and supersedes the original preparation package. Current upload status and evidence are in STORE_STATUS.md.

## Separate iPhone app
Version 1.0 (1), main bundle `com.illiagryniuk.capturearc.sender`, Share extension `.sender.share`, iOS 17+, iPhone. Xcode 26.6 project: `iPhoneSender/CaptureArcSender.xcodeproj`.

```sh
bash script/build_iphone_release.sh --export
```

Output: `dist/iPhone/CaptureArcSender.xcarchive` and `dist/iPhone/AppStore/CaptureArcSender.ipa`. Export uses App Store distribution with `get-task-allow=false`; it does not upload. Automatic signing needs the owner's already-authorized Xcode team. Do not revoke certificates or replace account credentials to build.

The iPhone icon is generated from the existing CaptureArc brand as an opaque 1024px asset:

```sh
swift script/generate_app_icon.swift --iphone
```

The separate app requires one new pairing. Its Keychain identity is deliberately separate from the old demo Sender; the existing demo remains installed and usable.

## Validation

```sh
swift test
swift test --package-path Packages/ClipboardDemoTransport
xcodebuild -project iPhoneSender/CaptureArcSender.xcodeproj -scheme CaptureArcSender \
  -destination 'platform=iOS Simulator,id=YOUR_QA_SIMULATOR' test
xcodebuild -project iPhoneSender/CaptureArcSender.xcodeproj -scheme CaptureArcSender \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO analyze
git diff --check
```

The transport package keeps its historical internal name and v1/v2 QR/Bonjour wire identifiers to remain compatible with the tested Sender. Demo sample controls and bundle-only feature gates have been removed from product UI. No third-party dependency was introduced.

## Store actions after local preparation
1. Sign in to App Store Connect. Verify current Mac version/build status and that 1.2 (4) is unused. Create a separate iOS record with the proposed name/SKU and registered bundle ID; confirm name availability.
2. Review the prepared metadata, privacy/support/terms website changes, and screenshots. Confirm account declarations and review contact. Publish the website changes only with owner approval.
3. Upload the Mac PKG and iPhone IPA using the normal Apple upload tools. Check server validation/processing, then use TestFlight for the final physical-device test if desired. Upload is separate from submission and public release.
4. Complete the remaining physical QA in RELEASE_CHECKLIST.md. Submit the Mac update first and retain manual release control.
5. After Mac 1.2 is public, submit the separate iPhone app. Add its confirmed App Store URL to the website. Request final owner approval before each public release.

Do not distribute to Work-Horse, submit Voice Transcript, or change system-wide permissions, networking, or firewall settings as part of this handoff.
