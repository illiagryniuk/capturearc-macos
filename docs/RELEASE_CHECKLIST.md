# Release Checklist

## Release recommendation

Ready for PR; blocked for App Store submission pending owner/account actions

## Summary

The requested functional regressions are fixed and the notch shelf has been redesigned and live-tested. CaptureArc now also has a sandboxed Mac App Store build path, release branding, metadata, privacy materials, and store screenshots. Launch at Login remains available through the native macOS service.

## What changed

- Added read-only discovery and polling for the current macOS Screenshot destination.
- Added simultaneous monitoring of the automatic source and one optional authorized folder.
- Added Spotlight-based filtering so the automatic source accepts screenshots and screen recordings but rejects ordinary media.
- Added source-specific health state, baseline handling, de-duplication, and bounded metadata retries.
- Rebuilt the idle notch surface as a stroke-only U-shaped rim while preserving the larger transparent click target and hover trigger; the expanded native shelf retains its physical camera cutout and colored glass chrome.
- Reworked the arrival motion so the source halo and curved lower-right-to-notch flight start together with zero programmed delay, plus an immediate reduced-motion fade.
- Replaced the disabled login placeholder with a working `SMAppService.mainApp` toggle and clear status/error states.
- Updated onboarding, Settings, README, telemetry, build signing, and focused test coverage.

## Why it changed

The previous app watched only `~/Pictures/Notch Captures`, while this Mac saved screenshots to `~/Desktop`. The initial compact redesign also painted a larger filled area than the desired notch-hugging affordance, and the first handoff revision could visually pause before moving. The changes align the app with the actual macOS save destination, leave only a restrained idle rim around the notch, and make the post-thumbnail handoff continuous.

## Marketing approval

Not applicable. This was a native product functionality and UI/UX change, not a website marketing workflow. The visual result was reviewed against the user's requested notch-wrap hierarchy and motion intent.

## Validation status

- Build: passed.
- Tests: 29 passed, 0 failed.
- App Store sandbox authorization and relaunch persistence: passed.
- Signed app launch: passed.
- Automatic real screenshot ingestion: passed.
- Ordinary Desktop media exclusion: passed.
- Immediate arrival timing, visible continuous lower-right-to-notch path, and event de-duplication: passed.
- Stroke-only idle rim, transparent interaction geometry, and expanded shelf visual/geometry QA: passed.
- Launch at Login code and tests: passed. The earlier live on/off round trip remains valid; fresh final-build inspection showed the user's switch currently enabled, and QA did not change it.
- Full details: `docs/VALIDATION.md`.

## Release blockers

- None for opening a PR.
- Public distribution is blocked by Apple account agreements/compliance, public support/privacy URLs, final owner decisions, and Mac App Store distribution signing assets. See `release/AppStore/READINESS.md`.
- Release still requires explicit user approval.

## Risks

- The automatic source relies on Spotlight screen-capture metadata. Two bounded follow-up scans cover normal indexing lag, but a future macOS metadata regression could delay a capture.
- Motion begins from the observed lower-right system-thumbnail area after file finalization. A future macOS change to when screenshot files become visible could require retuning the handoff.
- The live Launch at Login check covered registration and unregistration, not an actual logout/login boot cycle.
- The physical-notch and fallback external-display geometry have unit coverage, but the final live visual pass used one built-in notched display.
- Reduce Motion and Reduce Transparency are implemented, but their system settings were not toggled live in this pass.
- The visible idle rim is much smaller than its transparent 308×56 click target. This improves discoverability without a slab, but a very crowded menu bar should be checked for adjacent-item click interference.
- On displays without a physical notch, the idle fallback is intentionally a minimal 72-point arc and therefore less discoverable than the notched affordance.
- Moving or deleting the development app bundle after enabling Launch at Login can invalidate the stored bundle path; a release build should be installed in Applications.

## Suggested manual QA

- Install the release-signed app in Applications, enable Launch at Login, log out and back in, and confirm one quiet menu-bar launch.
- For the direct build, change Screenshot → Options → Save to while CaptureArc is running and confirm the displayed source switches within three seconds.
- For the App Store build, authorize a folder in CaptureArc, choose that same folder in Screenshot → Options → Save to, and confirm access survives a relaunch.
- Test full-screen apps, every Space, an external display above/beside the MacBook display, and a Mac without a physical notch.
- Test a crowded menu bar and confirm the transparent collapsed target does not obstruct nearby menu-bar controls.
- Toggle Reduce Motion and Reduce Transparency and confirm the fade/opaque alternatives.
- Test both screenshots and longer screen recordings, including markup before save.
- Exercise multi-select, Quick Look, copy, drag, share, Finder reveal, and move-to-Trash with disposable files.
- Validate a Developer ID/notarized artifact with Gatekeeper before public distribution.

## Suggested PR title

Fix automatic screenshot capture and refine the notch handoff

## Suggested PR description

- Follow the real macOS Screenshot save location automatically and filter system captures from ordinary media.
- Render the idle shelf as a stroke-only rim while retaining reliable transparent interaction geometry and the expanded physical-notch cutout.
- Start the lower-right-to-notch handoff immediately with no stationary lead-in, while retaining reduced-motion support.
- Make Launch at Login functional with native ServiceManagement state and errors.
- Add source, geometry, timing, login, and regression tests plus updated validation documentation.

## Final user action required

Review the local app and approve the PR/release boundary. Do not deploy, merge, notarize, or distribute publicly without that approval.
