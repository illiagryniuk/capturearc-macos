# Validation Results

Validated on 2026-07-10 on Apple silicon with macOS 26.5.1 and a built-in notched display.

## Validation summary

CaptureArc now passes package build, unit tests, signed-bundle integrity checks, live functional QA, and Apple's App Store processing for build 1.0.0 (2). The processed build is attached to macOS version 1.0, the listing draft is saved, and App Store Connect enables **Add for Review**. Only the explicit human review-submission gate and optional TestFlight smoke test remain.

## Commands detected

- SwiftPM: `swift build`, `swift test`, and `swift package describe`.
- Local app assembly and launch: `./script/build_and_run.sh --verify`.
- Runtime diagnostics: `./script/build_and_run.sh --logs` and `./script/build_and_run.sh --telemetry`.
- Bundle checks: `codesign`, `plutil`, `file`, `spctl`, and `sfltool`.

## Commands run

- `swift package describe` — passed; the executable and test targets resolved.
- `swift build` — passed without compiler warnings.
- `swift test` — passed, 29 tests and 0 failures.
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
- The idle panel remains a forgiving 308×56 interaction target around the 220×38 physical notch, with a 328×66 hover trigger. Only a 224×39.25 cyan-to-indigo-to-violet U-shaped rim is drawn; all other idle pixels remain transparent, so there is no filled slab behind the notch.
- The collapsed accessibility button exactly matches the 308×56 panel. Its accessibility description reports “Open Capture Shelf” with the current count, and its hint explains that it shows recent screenshots and screen recordings.
- Hover expanded the shelf to 680×438, with a transparent camera cutout, cyan-to-indigo-to-violet chrome, capture grid, and action bar. Pointer exit returned it to 308×56.
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
- TestFlight install on a second Mac/user account — build 2 is processed and available, but an external smoke test has not been run.
- Real logout/login cycle — registration state and Background Task Management state were verified, but the Mac was not logged out during QA.
- Reduce Motion and Reduce Transparency — code paths and reduced-motion timing are covered, but the system accessibility settings were not toggled live.
- External-display, multiple-display, full-screen-app, and every-Space visual QA — geometry has unit coverage, but live QA used the built-in notched display.
- macOS 13–15 runtime QA — the declared minimum is macOS 13, while this run used macOS 26.5.1.

## Build result

Passed. `dist/CaptureArc.app` is a valid native local build. `dist/AppStore/CaptureArc.app` build 2 is a universal arm64 + x86_64 bundle signed with the Apple-issued Mac App Distribution identity and matching provisioning profile. `dist/AppStore/CaptureArc-1.0.0.pkg` is signed with the Apple-issued Mac Installer Distribution identity, has a valid Apple certificate chain, contains no quarantine metadata, and completed Apple processing. The App Store candidate has App Sandbox enabled, contains `PrivacyInfo.xcprivacy`, and declares macOS 13.0 as the minimum system version.

## Test result

Passed: 29 tests, 0 failures. Coverage includes zero-delay arrival timing, file stability, grouping, automatic-source baselining and de-duplication, distribution-channel behavior, media classification, Launch at Login status mapping, notch geometry, the stroke-only idle rim, cutout layout, retention safety, screenshot-location resolution, and system-capture filtering.

## Lint result

Skipped: no lint tooling is configured.

## Typecheck result

Passed through `swift build`; there is no separate typecheck target.

## Blockers

- No blocker for PR or local product review.
- No unresolved App Store Connect validation blocker; build 1.0.0 (2) is processed, attached, and the version is ready to be added for review.
- Manual user approval is required before any release, deployment, merge, or public distribution.
