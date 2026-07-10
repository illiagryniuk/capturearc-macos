# CaptureArc

CaptureArc is a privacy-first macOS utility that keeps screenshots and screen recordings in a native shelf built around the MacBook notch (or a top-center pill on displays without a notch).

## MVP behavior

- The direct/local build follows the current macOS Screenshot destination automatically and can also watch one optional user-selected folder.
- The Mac App Store build watches one folder explicitly authorized through the standard macOS folder picker, as required by App Sandbox.
- Filters the automatic source using macOS screen-capture metadata, so ordinary Desktop images are not added to the shelf.
- Waits for image and movie files to finish writing before indexing them.
- Opens a native shelf when the pointer rests over the notch.
- Hands the macOS floating thumbnail off from the lower-right corner into the notch after the system thumbnail finishes, with a reduced-motion alternative.
- Supports multi-selection, keyboard actions, Quick Look, file-URL dragging, native sharing, Finder reveal, copying, and moving files to Trash.
- Supports Launch at Login through the native macOS login-item service.
- Uses only local files and public macOS APIs. It does not require Screen Recording, Accessibility, Input Monitoring, camera, microphone, or Full Disk Access permissions.
- Stores the selected folder as a security-scoped bookmark for future sandbox compatibility.

## Run locally

```bash
./script/build_and_run.sh --verify
```

The script builds the SwiftPM executable, stages `dist/CaptureArc.app`, launches the real app bundle, and verifies that the process is running. The Codex desktop Run action uses the same script.

Other modes:

```bash
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

## Screenshot discovery

The direct/local build reads the current `com.apple.screencapture` destination without changing it, falls back to `~/Desktop` when macOS has no explicit preference, and checks for destination changes while the app runs.

The sandboxed App Store build asks the person to authorize a folder, then instructs them to choose the same folder in Shift–Command–5 → Options → Save to. It never reads Screenshot preferences or files outside that folder.

macOS exposes the finalized capture file after its floating-thumbnail step. CaptureArc immediately continues that motion with a curved flight from the lower-right edge into the notch; its color cue starts at the same moment, without a stationary staging pause. When **Show Floating Thumbnail** is disabled in Shift–Command–5 → Options, the finalized file normally arrives sooner. Clipboard-only screenshots do not create a file and therefore do not appear on the shelf.

## Mac App Store candidate

```bash
./script/build_app_store.sh --verify --run
```

Release metadata, privacy/support-page drafts, screenshots, and the remaining submission gates live in `release/AppStore/`.

## Public pages

- Product: <https://illiagryniuk.github.io/capturearc-macos/>
- Privacy Policy: <https://illiagryniuk.github.io/capturearc-macos/privacy.html>
- Terms of Use: <https://illiagryniuk.github.io/capturearc-macos/terms.html>
- Support: <https://illiagryniuk.github.io/capturearc-macos/support.html>

GitHub Actions publishes these pages from `release/AppStore/site/` after changes land on `main`.
