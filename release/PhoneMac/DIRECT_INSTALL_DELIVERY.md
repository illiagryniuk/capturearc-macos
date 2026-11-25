# Direct Mac delivery and iPhone installation — 25 November 2026

The requested install deliverables were prepared without changing either App Store draft.

## Mac download

- File: **CaptureArc-1.2.2-Universal-1GiB.zip**; 3,472,252 bytes.
- Library ID: `libfile_fde3_f-f0336254f56c81918292988e42f74322_e707b48f09608191b24761884be6fbfd`; version 0. Library create succeeded and local identity metadata was applied using the current helper.
- ZIP SHA-256: `0f1b755bcf9a78a15edb994e411345ebc9d07406a6ba701b3e818ec6d14f1f36`.
- App: **CaptureArc 1.2.2 (5)**, `com.illiagryniuk.capturearc`, universal arm64 + x86_64, minimum macOS 13.0. This is the full app with the From iPhone shelf and 1 GiB file route, not the Clipboard Demo or the old 1.2.1 download.
- The two architecture executable text sections exactly match the tested Mac 1.2 (5) source candidate. Direct-distribution version metadata was advanced separately; the uploaded App Store archive remains 1.2 (5).
- Existing cloud Developer ID signing was reused. The leaf certificate SHA-1 is `19508C15A2BEB96C967FCD21A59B7FD14870AE2E`, issued 2026-11-19 and valid through 2027-02-01; it matches the previously used certificate. No new signing key was required.
- Xcode Developer ID/notarization upload and notarized export succeeded. Stapling, strict deep codesign verification, and Gatekeeper assessment passed on both the export and a fresh ZIP extraction: **accepted; source=Notarized Developer ID**.
- Sandbox, network client/server, user-selected file access, app-scoped bookmarks and Hardened Runtime are retained. PSK/TLS code is unchanged. Production Mac files were not replaced or launched for this delivery.

Installation: unzip, quit the older CaptureArc, and copy CaptureArc.app into Applications. Existing receiving identity/data use the same application bundle. To enable files above the legacy 10 MiB bound, pair Sender with the updated Mac's newly displayed capability-bearing QR once. An older saved QR intentionally retains the legacy route and returns an explicit upgrade/rescan message for larger files.

## iPhone installation

- Exported the existing **Sender 1.0 (2)** Release archive for the authorized physical phone using the existing Apple Development identity/profile.
- `devicectl device install app` returned **App installed** for `com.illiagryniuk.capturearc.sender`. A subsequent device query confirmed version **1.0**, build **2**, and normal process launch returned **Launched application**.
- The update was in place: no uninstall, pairing clear, user-content read, permission change or device reset. App and Share extension preserve team `6S36MAPK89` and the shared Keychain group `6S36MAPK89.com.illiagryniuk.capturearc.sender`. Pairing contents were deliberately not read.
- App and extension strict signatures verified. The installed Release export contains no XCTest bundle/private QA pairing resource. Minimum iOS 17.0; existing development profile expires 2027-06-06.
- Device-install IPA SHA-256: `eeaebec8957866efd954a2670af831e1e48b41ec6bf5d5c0bd4e9bb97fc157ea`.
- Direct installation succeeded, so no TestFlight fallback or testing-group change was needed.

## Verification boundary

The earlier automated transport, provider, storage, size-boundary and memory tests cover this unchanged code. The actual physical Share-sheet send, large-file receipt/ACK and Finder drag have not been verified: native UI control stalled during the preceding QA, and the isolated Mac Bonjour readiness problem remains unresolved. Installation, launch, artifact identity, signatures/notarization and Library delivery are verified; this document does not claim the remaining end-to-end release gate passed. No owner test was requested, and neither app was submitted or published in this install task.
