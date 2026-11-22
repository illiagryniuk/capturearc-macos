# Release Checklist

**Current status:** See [STORE_STATUS.md](STORE_STATUS.md). Both builds uploaded successfully. The owner has authorized App Review submission; neither submission is confirmed and public release remains manual.

## Release recommendation
**Ready for PR. Public release is blocked pending store access and final physical QA.**

## Summary
Prepare the existing CaptureArc Mac product's 1.2 update and a separate CaptureArc Sender iPhone 1.0 app. Signed distribution artifacts, source, screenshots, review notes, store copy, privacy/support/terms drafts, reproducible build commands, and local validation evidence are included.

## What changed
- Integrated the tested TLS/PSK transfer, final ACK lifecycle, Share input handling, large text/file limits, and until-stopped pairing.
- Added the Mac From iPhone card grid, photo previews, full-text/file drag providers, and automatic text clipboard copy.
- Added persistent private received storage and Keychain-backed pairing restoration, individual removal/clear, and an iPhone-only setup path.
- Added a separately identified iPhone app and Share extension with restricted Keychain sharing, English/Ukrainian strings, permissions, privacy manifests, an opaque branded icon, and App Store export configuration.
- Prepared both listings, review instructions, updated public-site drafts, and genuine synthetic-content screenshots.
See CHANGED_FILES.md for the complete file list.

## Why it changed
The owner asked for fast sharing of selected long text, photos, and links from iPhone, with visual draggable cards and immediate text pasting on Mac, then requested a Mac product update and a separate iPhone app prepared for release.

## Marketing approval
The separate CaptureArc Sender record and name are confirmed (Apple ID 6837705742). The Mac 1.2 listing and six screenshots are saved. The owner authorized both App Review submissions on November 21. The iPhone listing, private review contact, screenshots, pricing/territories, and remaining store fields still need completion. Updated public support/privacy/terms pages are prepared locally and must be published and checked before review. Public app release remains manual.

## Validation status
62 automated tests pass. Signed Mac PKG and iPhone IPA pass local integrity, identity, entitlement, resource, deployment-target, and privacy/icon checks. See VALIDATION_RESULTS.md and artifact-verification.json for supporting evidence and SHA-256 values.

## Release blockers
1. **App Store Connect session.** Restore the signed-in Chrome connection. Both records already exist. The latest tab returned to Apple's login page, and browser control could not attach.
2. **Final physical check.** The new Sender identity is installed, and CaptureArc Release QA on Hoover has a fresh pairing QR. Scan once in the separate app, share a photo, and verify that its Mac card drags successfully into a real destination app. Also finish the focused device checks below before release. Previous demo ACK/autocopy confirmations remain recorded and do not need diagnostic repetition.
3. **Store preparation completion.** Both builds are delivered; do not upload them again. Confirm Mac 1.2 (4) processing/selection and iPhone 1.0 (1) selection, upload the iPhone screenshots, and complete current privacy/age/content-rights/account declarations and verified review contact. No App Review submission is confirmed.
4. **Public materials and review access.** Publish and verify the prepared support/privacy/terms pages through the authorized release workflow. Make sure Apple's iPhone reviewer can obtain the required Mac 1.2 companion. The owner has authorized review submission of both apps; retain manual public release so the paired apps can be released together after approval.

## Risks
- Same-Wi-Fi networking requires peer access; isolated guest networks and sleeping/offline Macs can block transfer. There is no cloud fallback.
- A timeout can happen after the Mac stores an item if its acknowledgement is interrupted. Check the Mac before retrying to avoid duplicates. No automatic retry or exactly-once promise is made.
- Limits are explicit: five items per share, 10 MiB per photo/file, 1 MiB per text item, twenty stored cards. Clearing/removing received cards deletes local Mac copies, while iPhone originals remain.
- Restored pairing resumes reception only while CaptureArc is open; Stop Receiving revokes it. Received text replaces the Mac clipboard by the owner's requested design.
- Mac App Store PKG and iOS App Store IPA are upload artifacts, not a direct-download installer/sideload package for end users. The QA copy and development phone install are separate from production distribution.
- User content and pairing secrets must stay out of screenshots, logs, review attachments, and the release kit.

## Suggested manual QA
- First-run Camera/Local Network allow and deny/recover paths in the new phone identity.
- From Notes, selected text through the selection menu or copy/paste fallback; multi-page Unicode text should paste fully on Mac.
- One HEIC/JPEG photo, a five-photo batch, and a Safari link. Verify receipt, original bytes/openability, photo previews, and useful drag/drop into a chosen destination app.
- Relaunch Mac and phone; saved pairing should continue. Stop Receiving, relaunch Mac, and verify it stays stopped. Pair again and verify recovery.
- Lock/sleep/offline the Mac, confirm an honest failure, then recover. At a full shelf, remove a card and retry only the unsent item.
- Dynamic Type/VoiceOver, keyboard actions, light/dark appearance, and one minimum-version/Intel run if those environments are available.

## Suggested PR title
Prepare CaptureArc 1.2 and separate iPhone Sender 1.0

## Suggested PR description
CaptureArc can now receive user-selected text, photos, links, and files from the separate iPhone Sender app over an authenticated encrypted Wi-Fi connection. Received items appear as draggable cards, and accepted text is copied immediately to the Mac clipboard. Pairing and received cards persist across restarts; stopping reception revokes pairing.

Adds the iPhone Share extension and distribution identity, privacy/icon resources, release build scripts, updated store/site drafts, and screenshot assets. Local validation: 46 Mac + 7 transport + 9 iOS tests pass; universal Mac PKG and iPhone IPA export and signature checks pass. Public release remains gated on final physical QA, App Store record/processing checks, and owner approval.

## Final user action required
Finish the new-identity photo/drag check on Hoover, restore the signed-in Chrome session, and provide or enter the iPhone App Review email and phone number. App Review submission is already authorized. No further submission permission is needed once the checks and forms are complete. Public release remains under manual owner control.
