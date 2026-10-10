# Validation Results

Validated on 2026-10-10 on Apple silicon with macOS 26.5.1 and a built-in notched display. Earlier App Store processing evidence below is retained for build 1.0.0 (2); the new build 1.0.0 (3) has not been uploaded yet.

## Validation summary

The updated CaptureArc passes local build, 34 automated tests, visual UI inspection, sandbox runtime QA, and distribution package/signature checks. Exact notch activation replaces the previous proximity trigger, and the larger shelf now has separate Screenshots and Files sections with persistent folder tabs. Build 1.0.0 (3) is prepared locally but intentionally not uploaded until the owner completes hands-on testing and approves the release gate.

## Commands detected

- SwiftPM: `swift build`, `swift test`, and `swift package describe`.
- Local app assembly and launch: `./script/build_and_run.sh --verify`.
- Runtime diagnostics: `./script/build_and_run.sh --logs` and `./script/build_and_run.sh --telemetry`.
- Bundle checks: `codesign`, `plutil`, `file`, `spctl`, and `sfltool`.

## Commands run

- `swift package describe` — passed; the executable and test targets resolved.
- `swift build` — passed without compiler warnings.
- `swift test` — passed, 34 tests and 0 failures.
- `./script/build_and_run.sh --verify` — built, staged, signed, launched, and found the final app process.
- `codesign --verify --deep --strict --verbose=2 dist/CaptureArc.app` — passed.
- `codesign --verify --deep --strict --verbose=2 dist/AppStore/CaptureArc.app` — passed.
- `codesign -dvvv --entitlements - dist/AppStore/CaptureArc.app` — confirmed the minimal App Sandbox, app-scoped bookmark, and user-selected read/write entitlements.
- `plutil -lint` — passed for both Info plists, the privacy manifest, and App Store entitlements.
- `lipo -info dist/AppStore/CaptureArc.app/Contents/MacOS/CaptureArc` — confirmed arm64 and x86_64 slices.
- `pkgutil --check-signature dist/AppStore/CaptureArc-1.0.0.pkg` — confirmed an Apple-issued Mac Installer Distribution signature and valid Apple certificate chain.
- Recursive `xattr` inspection of the app and an expanded final package — confirmed no `com.apple.quarantine` attribute remains.
- Embedded provisioning-profile inspection — confirmed the app identifier and team match `com.illiagryniuk.capturearc`.
- `sfltool dumpbtm` — previously confirmed the CaptureArc login-item record during the successful on/off registration round trip. The final build was inspected without changing the user's current enabled state.
- `/usr/sbin/screencapture -p` — exercised the real macOS default screenshot destination and floating-thumbnail path.
- Transporter and App Store Connect — build 1.0.0 (2) was delivered, completed Apple processing, reached **Ready to Submit**, and was attached to macOS version 1.0.
- `APP_STORE_BUILD_NUMBER=3 ... ./script/build_app_store.sh --package` — produced a universal, distribution-signed build 1.0.0 (3) app and installer locally.
- Final build 3 installer SHA-256: `5c8b2f5ac897353d56622eecf2fd3ddff97e8718d590e740fe528678c48960d0`.
- Final extended-attribute inspection found expected local provenance metadata and no `com.apple.quarantine` attribute.
- Development-signed App Store configuration — launched with App Sandbox and the production entitlements, displayed the Files workspace, and presented the system folder authorization panel without an app fault.

## Passed checks

- The App Store build launched with App Sandbox enabled and showed the one-folder authorization onboarding instead of attempting to read system Screenshot preferences.
- The standard folder picker granted access to `~/Pictures/CaptureArc Captures`; a real new screenshot was detected, classified, and displayed in the shelf.
- After a full quit and relaunch, the app-scoped security bookmark restored access without another prompt.
- The App Store build exposed only three entitlements: App Sandbox, app-scoped bookmarks, and user-selected read/write file access.
- Five store screenshots were generated at Apple's accepted 2880×1800 size, uploaded, and ordered from `01` through `05`. Store name, subtitle, and keywords fit their limits; promotional text is 167 characters.
- Resolved the actual macOS Screenshot destination read-only, with `~/Desktop` fallback when no explicit location preference exists.
- Watched the automatic macOS source and the optional authorized folder simultaneously.
- Ignored an ordinary Desktop PNG whose Spotlight screen-capture metadata was absent; the supported capture count stayed unchanged through the immediate, +1 second, and +3 second scans.
- Accepted a genuine macOS screenshot with `kMDItemIsScreenCapture = 1`; the shelf count increased by one and exactly one `New capture finalized` event was emitted.
- Baseline files loaded without fake arrival events, and rescans did not duplicate the new capture.
- The final arrival flow has no programmed stationary lead-in: the thumbnail movement and source halo both begin immediately. Live finalization-to-flight logs measured 9 ms on the first run and 23 ms on the recorded run. Frame-by-frame screen-recording QA confirmed continuous lower-right-to-notch motion without a blank or stationary frame.
- The idle panel still draws the 224×39.25 cyan-to-indigo-to-violet U-shaped rim, but its window ignores mouse events while collapsed. Opening is now limited to the exact 220×38 physical-notch geometry; points on the surrounding shoulders no longer activate the shelf.
- The collapsed accessibility button exactly matches the 308×56 panel. Its accessibility description reports “Open Capture Shelf” with the current count, and its hint explains that it shows recent screenshots and screen recordings.
- Pushing the pointer into the notch expands the shelf to 820×540, with a transparent camera cutout, cyan-to-indigo-to-violet chrome, and dedicated Screenshots and Files sections. Pointer exit returns it to 308×56.
- The Files section displays a native folder picker, horizontal folder tabs, Finder-style icons and file metadata, nested-folder navigation, Open, and Show in Finder actions.
- File Shelf tests created a temporary folder, loaded folders before files, navigated to a nested folder, restored the folder tab and current path from an app-scoped bookmark in a second store instance, and closed the tab without changing the source files.
- The Settings window surfaced the automatic screenshot folder, optional extra folder, library state, shelf preferences, retention, and an enabled Launch at Login control.
- The Launch at Login implementation is unchanged and uses Apple's public [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp?language=objc) service. Its earlier live on/off round trip registered and unregistered successfully. Fresh final-build inspection showed the user's switch enabled with the correct “will open automatically” status; QA preserved that current state.
- Unified telemetry contained lifecycle, source, reconciliation, capture-finalization, animation, panel, hover, and login-item events without logging capture filenames or full paths.
- All exact QA screenshots created in the automatic source were moved to Trash after testing, and the shelf returned to 8 captures.
- The packaging script now accepts an explicit build number and strips downloaded-file quarantine metadata before signing. Build 2 retained the universal binary, minimal sandbox entitlements, valid app signature, and valid Apple installer certificate chain.

## Resolved submission issue

- Build 1.0.0 (1) failed Apple processing because the downloaded provisioning profile carried `com.apple.quarantine` into the package payload. The packaging source was corrected, build 1.0.0 (2) passed Apple processing, and no unresolved upload error remains.

## Skipped checks

- Lint — no lint command or configuration exists in the project.
- Separate typecheck — no standalone typecheck command exists; `swift build` compiled all production sources.
- TestFlight install on a second Mac/user account — build 2 is processed but does not contain this update; build 3 is not uploaded yet.
- Real logout/login cycle — registration state and Background Task Management state were verified, but the Mac was not logged out during QA.
- Reduce Motion and Reduce Transparency — code paths and reduced-motion timing are covered, but the system accessibility settings were not toggled live.
- External-display, multiple-display, full-screen-app, and every-Space visual QA — geometry has unit coverage, but live QA used the built-in notched display.
- macOS 13–15 runtime QA — the declared minimum is macOS 13, while this run used macOS 26.5.1.

## Build result

Passed locally. `dist/CaptureArc.app` is a signed native development build and is running for owner testing. `dist/AppStore/CaptureArc.app` build 3 is a universal arm64 + x86_64 bundle signed with the Apple-issued Mac App Distribution identity and matching provisioning profile. `dist/AppStore/CaptureArc-1.0.0.pkg` is signed with the Apple-issued Mac Installer Distribution identity and has a valid Apple certificate chain. The candidate has App Sandbox enabled, contains `PrivacyInfo.xcprivacy`, and declares macOS 13.0 as the minimum system version. App Store processing remains pending because upload is deliberately held for owner approval.

## Test result

Passed: 34 tests, 0 failures. New coverage verifies exact physical-notch activation geometry, safe relative paths, Finder-style sorting, folder-tab loading, nested navigation, bookmark restoration, selected-path restoration, and closing persistent tabs. Existing capture, animation, filtering, retention, launch-at-login, and distribution coverage also remains green.

## Lint result

Skipped: no lint tooling is configured.

## Typecheck result

Passed through `swift build`; there is no separate typecheck target.

## Blockers

- No blocker for PR or local product review.
- Build 1.0.0 (3) still needs an updated store screenshot, upload, Apple processing, and attachment to version 1.0.
- Manual user approval is required before upload/release submission, deployment, merge, or public distribution.
