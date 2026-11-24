# Large-file transfer implementation — 24 November 2026

This is an isolated source candidate, not a deployed release. Work is on Hoover in branch `codex/capturearc-large-file-streaming`, based on `b77d11ae10c1a2d7ebe8af13715c8673cc425c10` (the shelf-tab layout fix, parent `2437e10ccac82328233f65955497e9f192bc7e09`). The original release checkout, its uncommitted release documents, the layout QA checkout and instrumentation checkout are preserved. No GUI action was in flight on resumption.

The candidate supports files **up to and including 1,073,741,824 bytes (1 GiB)**. A `.txt` document remains a file card, without extracting its contents or changing the Mac clipboard. Selected text retains the existing 1 MiB limit and automatic clipboard behavior. Audio, ZIP archives and opaque backup files use the same file route without conversion, extraction or an extension allowlist. Directories must first be exported as a file/archive. Existing batches remain limited to five items, processed sequentially.

The implementation is shared by the iPhone file picker and Share extension and the Mac receiver. The tested inputs include actual `NSItemProvider(contentsOf:)` and registered file representations, an 11 MiB text document with a competing text preview, selected Unicode/attributed text, a web link, a photo, `.m4a`, `.zip`, and a synthetic custom `.vtbackup` provider. No personal recording or actual Voice Transcript export was opened. The audio fixture represents one hour at 48 kHz, mono, 16-bit PCM and has a valid WAV header; its size is 345,600,044 bytes. Longer/higher-rate exports still have to fit the byte limit.

## Protocol and resource bounds

- The existing Wi-Fi-only TLS 1.2 PSK authentication and pairing secret remain unchanged. No sandbox entitlement, firewall, VPN, permission, signing-policy or network-setting changes are part of this patch.
- A QR invitation may advertise optional `fileProtocol: 3`, preserving the existing QR prefix and fields. The existing saved secret is retained when the updated Mac displays a new QR. Older senders can still use legacy frames. A new sender with an old QR sends files up to 10 MiB using the legacy route; a larger file gets an explicit update-and-rescan error before transmission.
- Inside authenticated TLS, `CAF3` distinguishes a stream from the legacy length-prefixed JSON frame. A length-prefixed JSON metadata record and admission reply are each bounded to 4 KiB. Version, inclusive limit and 256 KiB chunk size are confirmed before file content is sent. Declared lengths, kind and safe filename are checked.
- One file stream is admitted at a time; the receiver retains its existing two-connection limit. Sender and receiver keep one 256 KiB chunk in flight and calculate SHA-256 incrementally. Photos and files no longer need whole-payload JSON/base64 on the new route.
- Source URLs are read under file coordination/security-scoped access where provided, copied into a private snapshot, and checked for size/modification changes. File-provider URL data is decoded through `NSURL`'s item-provider decoder; treating its binary property-list representation as a plain URL would force a costly full-content fallback. Per-chunk autorelease pools prevent Foundation read buffers accumulating inside a provider callback.
- Both sides check free disk space for the declared payload plus a 64 MiB reserve. The phone needs a temporary snapshot in addition to the original and any temporary copy supplied by the host. Mac staging is on the shelf's filesystem, so adoption is a rename instead of another full copy.
- Temporary directories/files use 0700/0600 permissions. Lease locks identify live staging directories; a subsequent transfer cleans abandoned, app-owned partials after process interruption while preserving live transfers. Ordinary cancellation, connection loss, hash failure and disk failure remove their partials immediately. No user files are deleted.
- A stalled connection has a 30-second idle deadline, renewed on actual completed network activity, and a two-hour total bound. Provider preparation has a 120-second deadline and cancellable, single-completion handling, including a host that never responds. User cancellation stops the file route without ending pairing.
- Progress distinguishes bytes sent from waiting for the Mac to save and verify. The receiver flushes the file, verifies its digest, adopts it into the shelf, and flushes/atomically replaces the manifest before positive acknowledgment. A failed commit cannot produce a success ACK. Keep Sender/the Share sheet open until receipt is confirmed; background transfer is not implemented. Interrupted transfers restart from the beginning; there is no resume protocol. If a final ACK is lost after a successful save, inspect the shelf before retrying to avoid a duplicate.
- File cards advertise file-backed drag representations and a file URL. They do not extract large text documents into inline strings.

The bundled source privacy manifests now declare file metadata access for app-owned/user-selected files (`C617.1`, `3B52.1`), storage preflight (`E174.1`) and elapsed-time deadlines (`35F9.1`), matching the implemented APIs and [Apple's documented reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). Existing tracking/collected-data settings are unchanged. Free-space quantities, timestamps and uptime values are not transmitted; storage rejection prevents receiving the file. These source entries are not an App Store Connect privacy submission.

## Evidence

All fixtures are synthetic. Reproducible checks run on Hoover, macOS 27.2.1 (26B131), Swift 6.4.2 / Xcode 27.2, Apple Silicon. macOS 13 and iOS 17 are compile targets, not claims of testing on every OS version.

| Check | Result |
|---|---|
| Native authenticated transport | 19 tests passed, including both legacy ACK lifecycle and streaming |
| Mac application tests | 52 tests passed, including retained shelf layout tests, restore, clipboard isolation, file drag representation and failed manifest commit |
| iOS 17.5 dedicated simulator | 15-test suite passed plus the added over-cap file-provider test passed separately: 16 cases total |
| iOS 27.2 dedicated simulator | All 16 tests passed, including exact-cap/hash/memory checks for both provider forms, over-cap rejection and cancellation of an unresponsive provider |
| Mac release configuration | Built successfully; arm64 binary targets macOS 13.0 |
| iPhone app and Share extension release configuration | Device-target build succeeded without signing/installation; targets iOS 17.0 |

Transport cases passed at 11,534,353 bytes (11 MiB + 17), 345,600,044 bytes (hour WAV), 1,073,741,823 bytes and exactly 1,073,741,824 bytes. Receiver-side SHA-256 matched source and saved-file hashes. A declared or source size of 1,073,741,825 bytes was rejected, as were zero, negative and `Int64.max` lengths. Further cases cover wrong PSK (existing authenticated transport), old pairing/large-file preflight, new sender/small file to a legacy receiver, cancellation followed by another transfer on the same pairing, a truncated snapshot, wrong digest, a silent peer, full shelf, preflight disk-full, mid-write disk-full, save failure, and abandoned/live staging leases.

Memory assertions require less than 64 MiB growth during the large-file workloads. The final full native run peaked at 103,940,096 bytes RSS with a 17,448,960-byte increase during the hour/near/exact-cap workload. The iOS 17.5 XCTest host peaked at 239,468,544 bytes, with only 507,904 additional bytes during the first 1 GiB provider import and no further peak increase for the explicit file provider. The iOS 27.2 XCTest host peaked at 293,814,272 bytes with no increase in its existing peak during either 1 GiB provider import. These are test-host measurements, not a physical Share extension memory certification.

Commands (from this worktree):

```sh
CAPTUREARC_LARGE_FILE_TESTS=1 swift test --package-path Packages/ClipboardDemoTransport
swift test
swift build -c release
xcodebuild -project iPhoneSender/CaptureArcSender.xcodeproj -scheme CaptureArcSender \
  -configuration Debug -destination 'platform=iOS Simulator,id=<dedicated-QA-simulator>' \
  -derivedDataPath DerivedData/LargeFiles CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
xcodebuild -project iPhoneSender/CaptureArcSender.xcodeproj -scheme CaptureArcSender \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData/LargeFilesDevice CODE_SIGNING_ALLOWED=NO build
```

## Deployment boundary — updated 24 November 2026

The implementation branch was pushed normally to the existing GitHub remote. Release source build numbers are Mac **1.2 (5)** and Sender **1.0 (2)**. Both distribution archives/exports succeeded using the existing Apple signing account, and Xcode returned **Upload succeeded** / **Uploaded package is processing** for both exact version/build pairs. This is delivery, not completed processing, build selection, App Review submission or public release. See [LARGE_FILE_RELEASE_STATUS.md](LARGE_FILE_RELEASE_STATUS.md) for artifacts and current gates.

An optional XCTest integration entry point now drives the actual `SharedItemLoader.loadOutgoing` and `DemoSender.transmit` APIs against a separately signed, sandboxed Mac QA process using unchanged production `IncomingTransferStore` and persistence code. Its fixtures cover selected text/link, a valid noisy PNG above 1 MiB, 11 MiB text document, valid hour WAV and exact 1 GiB backup. The QA wrapper uses a private pasteboard/container and does not read or change production pairings, clipboard, screenshots or recordings. Its invitation is injected privately into a local test bundle; shipping IPA verification confirmed no test bundle/private pairing resource is present. The test skips when the private resource is absent.

The physical test was blocked before launch: Xcode reported **Unlock Nothing to Continue** and **cannot launch CaptureArcShareTests ... because the device is locked**. The waiting test was stopped; no owner test action was requested. A subsequent targeted app-version query timed out, so the last confirmed phone version remains 1.0 (1), not a claim that the new candidate is installed. GUI automation launch attempts did not return and were interrupted. No actual Finder drag was completed.

The dedicated iOS 27.2 simulator-to-sandboxed-Mac attempt **failed** with a `deadline` before the first selected-text receipt; the QA manifest was absent. This integration attempt does not pass the physical/two-device gate. The passing native authenticated loopback and iOS provider tests above must not be presented as proof that the two-device Wi-Fi path works. No routing, Local Network permission, firewall, VPN or sandbox protections were changed to force a result.

App Review submission remains held until the integration/visual boundary and App Store access/declaration gates are resolved. No new scan/send test is requested from the owner; the prepared synthetic device test can run autonomously when the physical device is available to Xcode.

Additional network triage: the iOS simulator reports a satisfied Wi-Fi path, while the authenticated service endpoint did not reach ready during a five-second diagnostic. The diagnostic records observations and is not a successful transfer test. The cause of the earlier 30-second deadline is not established by these observations.
