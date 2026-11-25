# Current App Store handoff

This file supersedes the original offline-preparation status in the release kit.

## Authorization and release control

The owner authorized preparation and App Review submission of both apps on November 21, 2026. Keep manual public release selected on both records. Do not publish either app automatically, accept new agreements, change unrelated records, or bypass the final Hoover physical-device check.

## Verified App Store state

- Mac record: **6789554439**, CaptureArc: Screenshot Shelf. Version **1.2** is **Prepare for Submission**. Updated description, promotional text, keywords, release notes, review instructions, and six screenshots are saved. The original 1.1 (3) remains Ready for Distribution. Corrected Mac **1.2 (4) uploaded successfully on November 22 at 02:27 Kyiv time**, and Apple started processing it. The upload receipt identifies app 6789554439/build 4, with no warnings or errors. Do not upload build 4 again; check processing and attach it in the browser.
- Separate iPhone record: **6837705742**, **CaptureArc Sender**, bundle `com.illiagryniuk.capturearc.sender`, SKU `CaptureArcSender-iOS`. Version **1.0** is **Prepare for Submission**. Build **1.0 (1)** uploaded successfully and appeared in the Add Build dialog. It was selected and Save was clicked, but persistence was not confirmed before interruption. Inspect the current selection before doing anything else. **Do not upload build 1 again.**
- The iPhone screenshot panel showed **0 of 10** screenshots. The interrupted earlier screenshot upload did not complete. Upload the two prepared JPEG assets once through Apple's UI.
- iPhone description/promotional text/keywords/support URL/review details were blank at the last fresh read. Copyright and manual release persisted. The earlier Save failed because review phone/email were missing and the promotional text included an unsupported arrow character. Use the corrected plain-text promotional copy in IPHONE_METADATA.md.
- App Review contact first/last name can use the verified owner name, Illia Gryniuk. Email and phone number were blank on iPhone. The owner has been asked to provide or enter them. Do not infer them from a login address or unrelated contact.
- Neither app has an accepted App Review submission. Privacy, age-rating, account/compliance, pricing/availability, subtitle, and compatibility settings still require completion and verification.

Mac draft: https://appstoreconnect.apple.com/apps/6789554439/distribution/macos/version/inflight

iPhone draft: https://appstoreconnect.apple.com/apps/6837705742/distribution/ios/version/inflight

## Upload evidence

The workspace's `evidence/ios-app-store-upload.log` records `Upload succeeded` and `EXPORT SUCCEEDED`. Xcode's archive distribution receipt identifies Apple app 6837705742, build 1. The only reported warning is the **future April 2027 iOS 27 SDK requirement**; it did not reject this upload.

Mac's first upload attempt failed validation with error **90276**, because SwiftPM's translation resource bundle lacked `CFBundleIdentifier`. The packaging script now adds a stable identifier before signing. Universal builds, preserved translations, strict signatures, and installer signing passed; the corrected upload succeeded. No app behavior, permissions, transport security, or iPhone binary changed.

Corrected local Mac package: `dist/AppStore/CaptureArc-1.2.pkg`, version 1.2 (4), 3,321,226 bytes, SHA-256 `bfcc28facb7f735106785166700428676c9553bef34d2ed00617cb526fb3decd`. The original preparation package with SHA `5eb4ec45ed6ea64e3268d60f83c848360317c1a6651c019ec065871dd5e7cfa9` is superseded.

Success evidence: workspace `evidence/mac-app-store-upload-resource-id.log` and `evidence/mac-upload-receipt.json`. The authoritative uploaded archive is `artifacts/Mac-Release-ResourceID/CaptureArc.xcarchive`; its distribution event says `Uploaded to Apple` for app 6789554439/build 4. The prior `Mac-Release` archive records the failed attempt and must not be retried.

## Physical QA gate

The separate development-signed Sender identity is installed on the paired iPhone Nothing. The isolated CaptureArc Release QA app on Hoover has receiving enabled and its QR shown. Its received-item manifest still contained zero items at the November 22 check. There is no final-identity photo/ACK/drag success evidence yet.

iPhone Mirroring could not find the phone and offered first-time setup. Setup was not enabled. The owner was asked to scan in the new CaptureArc-icon Sender, send synthetic text and a non-private test photo, and verify successful receipt and dragging the photo card into another app. Previous demo receipt/paste confirmations remain valid baseline evidence but do not satisfy this final check.

## Current access blocker

Opening Transporter was interrupted. No Mac upload was initiated through it. On reconnect, Chrome's CaptureArc tab was at the App Store Connect login page, and browser control could not attach. Restore the authenticated Chrome connection before completing metadata or submission. Do not repeat the iPhone upload or assume a clicked Save persisted.

## Remaining order

1. Restore App Store Connect access; verify iPhone build selection before any change.
2. Verify processing and select the successfully uploaded Mac 1.2 (4) candidate; do not repeat the upload.
3. Complete the iPhone screenshots, corrected listing, verified private review contact, and remaining store information for both apps.
4. Verify the actual iPhone-to-Hoover ACK, photo preview, and cross-app drag with synthetic data.
5. Publish the prepared accurate support/privacy materials through the authorized release workflow; confirm the live pages.
6. Submit each app for review, recording each separate accepted status, with manual public release retained. The iPhone review must have access to its required Mac 1.2 companion; supply a truthful review route if submitting both before the Mac release.

The original Library ZIP is superseded by the replacement release kit containing the packaging fix, corrected local Mac package, upload receipts, and this status. Neither kit is evidence of App Review submission.
