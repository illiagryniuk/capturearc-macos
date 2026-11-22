# Validation Results

**Store status update:** See [STORE_STATUS.md](STORE_STATUS.md) for subsequent iPhone upload/processing evidence and current blockers. The local validation results below are unchanged; the original store-access and upload notes are historical.

November 22: fixed Mac App Store validation error 90276 by adding the missing SwiftPM resource bundle identifier during packaging. Rebuilt both architectures, verified the preserved English/Ukrainian resources, strict app signature, installer certificate, shell syntax, and Git whitespace. The corrected Mac 1.2 (4) upload succeeded with no warnings/errors. The 62 application tests were not repeated for this packaging-only metadata change.

## Validation summary
Prepared on Hoover on November 21, 2026. **62 automated tests pass**: 46 Mac, 7 transport, 9 iPhone Share-input tests. Universal Mac App Store PKG and separately signed iPhone App Store IPA built and verified locally. This is ready for code review and final physical QA; App Store submission/public release is not yet cleared.

## Commands detected
SwiftPM `swift test`, separate transport package tests, the existing Mac App Store packaging script, the iPhone Xcode scheme's tests/build/archive/analyze actions, `codesign`, `pkgutil`, `plutil`, `lipo`, `sips`, and `git diff --check`. No repository lint configuration or standalone typecheck command exists. Swift compilation performs typechecking.

## Commands run
- `swift test` — 46/46 pass after final Mac code changes.
- `swift test --package-path Packages/ClipboardDemoTransport` — 7/7 pass.
- `xcodebuild ... -destination 'platform=iOS Simulator,id=26DCFEFA-E8D3-40F4-892B-1C3E65ACC5F4' test` — 9/9 pass after final iPhone code changes.
- `xcodebuild ... -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO analyze` — succeeds.
- `APP_STORE_PROVISIONING_PROFILE=... bash script/build_app_store.sh --package` — universal Mac release build and signed installer succeed.
- `bash script/build_iphone_release.sh --export` — archive and App Store export succeed; no upload.
- `codesign --verify --strict --deep` on the Mac app, exported iPhone app, and exported Share extension — pass.
- `pkgutil --check-signature` — Mac installer has valid Apple-issued Mac App Store installer identity.
- `lipo -info`, Info.plist/entitlement assertions, privacy manifest checks, icon and screenshot checks — pass.
- `bash -n` on the build scripts and `git diff --check` — pass.

## Passed checks
- Complete long Unicode text and paragraphs survive provider loading, framing, Mac storage, and clipboard copy. Tests exercise ten-page-sized text and the 1 MiB text boundary.
- Original photo/file bytes and safe filenames survive staging; previews are bounded and respect orientation. File URL and original data representations are offered for dragging.
- The 10 MiB transfer bound, rejected/expired invitations, wrong TLS key, stopped receiver, delayed ACK readers, and accepted/rejected ACKs are tested.
- Private-pasteboard tests verify rejected items and non-text items do not overwrite the clipboard. Restoring saved cards also leaves it alone.
- Persistent shelf restores long text and files, rejects a full shelf without losing items, removes owned files, and preserves a damaged manifest instead of overwriting it.
- New iPhone bundle/extension use their own restricted shared Keychain group. Exported distribution builds have `get-task-allow=false`.
- Mac keeps App Sandbox, Hardened Runtime, and both network client/server entitlements. Existing authorized-folder entitlements remain intact.
- Final iPhone app icon and generated App Store screenshots have no alpha channel. Phone screenshots are 1206×2622; new Mac screenshot is 2880×1800.
- Signed isolated Mac QA app launches, renders photo/text/link cards, restores cards after relaunch, resumes an active pairing, and keeps a stopped pairing stopped. Final first-run UI allows iPhone sharing without choosing a screenshot folder.
- The separate development-signed iPhone companion installed successfully on the existing paired phone. No uninstall, firewall/VPN changes, or production Mac replacement was performed.
- Simulator manual pairing with an inactive fixture and ordinary text entry work. Its test pairing was forgotten after screenshots; the dedicated simulator was shut down.

## Failed checks
No unresolved automated test or build failures. The first transport run compared a localized readiness string to a fixed Ukrainian string; updating the test comparison resolved it. The first opaque asset renderer used an unsupported RGB AppKit context; it was replaced with an opaque Core Graphics context and the resulting icon/screenshot were checked again. These are resolved preparation issues, not claims of successful store processing.

## Skipped checks
- App Store server validation/processing and live record status: browser is signed out; sign-in requested.
- Physical QR/Share/receipt with the final separate app identity and actual cross-app drag: requested from the owner. The automation's drag call cannot address the notch panel (`noWindowsAvailable`); no successful drag is claimed.
- Same-host simulator transfer is not counted as a Wi-Fi path test. Production transport still requires Wi-Fi.
- Intel execution and macOS 13 execution: universal binary/deployment target verified, but no corresponding runtime is attached.
- TestFlight distribution, real device first-install permission denial/recovery, five-photo batch, sleep/wake and offline recovery, and final store accessibility checklist require the final device/release pass.

## Build result
Pass locally. Mac: **CaptureArc 1.2 (4)**, `com.illiagryniuk.capturearc`, macOS 13+, arm64/x86_64, existing Mac App Store signing. iPhone: **CaptureArc Sender 1.0 (1)**, `com.illiagryniuk.capturearc.sender`, iOS 17+, separate Share extension, Apple distribution export. Neither package is submitted.

## Test result
62 pass, 0 unresolved failures. Earlier real-phone demo receipt and immediate Mac paste were confirmed by the owner in this conversation. Those confirmations establish the working baseline; they are not substituted for the final app-identity/device checks above.

## Lint result
No configured lint tool; shell syntax, plist validation, and Git whitespace checks pass.

## Typecheck result
Pass as part of SwiftPM debug/release builds and Xcode simulator/device builds. No new third-party dependency.

## Blockers
App Store Connect sign-in/current-record verification, final physical-device QA, reviewed account/store declarations, website publication approval, and owner approval before public release. The release checklist names the exact remaining actions.
