# Release Checklist

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
Drafts are prepared; owner approval is still needed. No public website or store metadata has been changed. Confirm the separate app name is available, free pricing/territories, the final screenshot order, and the publish date. Add the iPhone's real App Store URL after its record exists.

## Validation status
62 automated tests pass. Signed Mac PKG and iPhone IPA pass local integrity, identity, entitlement, resource, deployment-target, and privacy/icon checks. See VALIDATION_RESULTS.md and artifact-verification.json for supporting evidence and SHA-256 values.

## Release blockers
1. **App Store Connect session.** Sign in in the prepared CaptureArc release tab. Verify the current Mac 1.1 status and unused Mac 1.2 (4) number; create the separate iPhone record for `com.illiagryniuk.capturearc.sender` with confirmed name/SKU. No store record status is assumed from old release notes.
2. **Final physical check.** The new Sender identity is installed, and CaptureArc Release QA on Hoover has a fresh pairing QR. Scan once in the separate app, share a photo, and verify that its Mac card drags successfully into a real destination app. Also finish the focused device checks below before release. Previous demo ACK/autocopy confirmations remain recorded and do not need diagnostic repetition.
3. **Store preparation completion.** Upload the verified packages, wait for server processing, attach the correct builds and screenshots, complete current privacy/age/content-rights/account declarations using the owner's actual details, and review contact information. No upload/submission happened during this preparation.
4. **Public materials and release approval.** Approve and publish the prepared website updates, then approve App Review submission and later public release. Release the Mac update before the separate iPhone app so its required companion is available.

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
Finish the new-identity photo/drag check on Hoover and sign in to App Store Connect. After those checks and store processing are complete, review the concrete listings/builds and approve submission/public release. The global project rule and Release Reviewer explicitly require manual approval before release; this preparation does not publish or deploy anything.
