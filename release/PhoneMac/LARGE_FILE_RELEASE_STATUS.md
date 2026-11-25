# Large-file candidate delivery — 24 November 2026

**Delivered to Apple; not submitted for App Review or published.** The two-device/visual release gate remains open. Manual public release remains the intended setting; no release-selection setting was changed.

| App | Candidate | Delivery result | Review status |
| --- | --- | --- | --- |
| CaptureArc, Apple ID 6789554439 | 1.2 (5), `com.illiagryniuk.capturearc` | Xcode: Upload succeeded; uploaded package is processing | Not submitted; existing draft selection was not changed |
| CaptureArc Sender, Apple ID 6837705742 | 1.0 (2), `com.illiagryniuk.capturearc.sender` | Xcode: Upload succeeded; uploaded package is processing | Not submitted; existing draft selection was not changed |

Xcode delivery used the existing authorized Apple account/certificates. The upload log's host timestamps use UTC+02; delivery completed at approximately **2026-11-24 23:51 UTC**. The browser's App Store Connect session was signed out. Normal saved-credential autofill did not fill its password field; no password was extracted or submitted. GUI automation later failed to return on isolated QA launch attempts and was interrupted. Apple receipt email search had no matching new result yet; successful delivery is supported by Xcode's returned status, not an assertion that processing/selection is complete. Do not duplicate these uploads.

## Verified local exports

- Mac: `dist/AppStore/CaptureArc-1.2.pkg`, SHA-256 `ce9b6b6eda1dde4a0fcf729b011f9d13a08386b3754899f3669ce966f55bfb5e`. Universal arm64 + x86_64, minimum macOS 13.0, version 1.2 (5). App and installer signed with the existing Mac App Store distribution identities. Strict code-signature verification and package signature verification passed; sandbox, network client/server, user-selected file access/bookmarks and Hardened Runtime retained. Embedded SwiftPM resource bundle identifiers validated by the packaging flow.
- iPhone: `dist/iPhone/AppStore/CaptureArcSender.ipa`, SHA-256 `705a171d82a45ad41ec9ac4ceee21173302857a23e140d31b1462a5db9b5474e`. App and `.sender.share` extension are 1.0 (2), arm64, minimum iOS 17.0. Archive and App Store export succeeded; both strict signatures verified. No XCTest bundle/private QA pairing resource is included.
- These hashes identify the retained local exports. Xcode re-exported the same archives for delivery; the upload service did not return a downloadable final-package digest.
- The Mac `.pkg` is an App Store delivery artifact, **not** a standalone notarized Developer ID installer. No direct-distribution artifact is represented as ready.

The Mac universal build script now uses separate SwiftPM scratch directories per architecture. On the installed Swift toolchain, both triples otherwise returned the same `.build/out/Products/Release` path, leaving two x86_64 inputs and causing `lipo` to fail. Rebuilding with isolated architecture paths produced and verified both slices.

## Verification and outstanding gates

[Full test evidence](LARGE_FILE_STREAMING_VALIDATION.md) records 19 transport tests, 52 Mac tests, iOS 17.5/27.2 provider tests, exact/near/over 1 GiB boundaries, hour-like WAV, SHA-256, resource bounds and failure cleanup. The highest verified byte bound is **1,073,741,824 bytes inclusive**, not an unlimited or universally fastest file size. Selected text stays at 1 MiB; `.txt` documents use streaming file cards. Both updated apps and a newly scanned capability-bearing pairing QR are required above the old peer's 10 MiB bound.

Autonomous paired integration was attempted through the real Share provider and sender APIs against a signed, sandboxed Mac QA process using unchanged production receiver/store code. Physical launch was blocked by the locked iPhone; the simulator attempt timed out before its first synthetic text receipt. The Mac listener was ready and bound to a TCP port, but no received-item manifest was created. This is an unresolved integration failure, not a pass. The new optional tests contain no embedded token and skip without a private local QA resource.

Actual iPhone acknowledgment for a large file, a real Share-extension interaction, and Finder drag of a received synthetic photo/file remain unverified. No personal content was used. No network, privacy, firewall, VPN or sandbox protection was altered. Neither failing nor unverified integration is treated as permission to submit.

The last saved record evidence (22 November, not re-read as current) also leaves Sender **Content Rights** unset and its **Data Not Collected** privacy declaration at the final publication/accuracy attestation. The earlier automatic approval review rejected saving the Content Rights answer because broad release authorization does not establish the owner's factual declaration. No new declaration or legal agreement was accepted. These fields need the owner's factual confirmation; they cannot be guessed. The prior verified App Review contact is already recorded.

The next release step is to complete the prepared autonomous paired test when the device is available to Xcode and GUI control is functional, reconcile processed builds 5/2 and the saved declarations in the authenticated App Store Connect session, then select and submit the verified builds while retaining manual release. The user is not being asked to repeat a scan/send test.

Additional network triage: the iOS simulator reports a satisfied Wi-Fi path, while the authenticated service endpoint did not reach ready during a five-second diagnostic. The diagnostic records observations and is not a successful transfer test. The cause of the earlier 30-second deadline is not established by these observations.

The host Bonjour browser saw other existing CaptureArc services, but the private QA service was absent during the four-second check. The QA TCP listener itself reported ready. This narrows the failed attempt to discovery/connection readiness before payload transfer; it does not establish a new file-size failure or identify the underlying OS/network cause.

## Follow-up investigation — 25 November, before 05:00 UTC

The isolated Apple Development-signed, sandboxed QA bundle was launched normally through Launch Services (`open -n`), with Hardened Runtime and the production network entitlements retained. The production Mac store/persistence code is unchanged; the isolated transport copy adds observation-only callbacks. TCP reached ready and LISTEN. A service-registration callback did not arrive. A Network.framework browser reported ready without discovery results; a direct DNS-SD browse returned creation status 0 and dispatch-queue status 0, without a result/error callback during the bounded observation. The host DNS-SD browser still found other existing CaptureArc records, but not the exact QA service. No `kDNSServiceErr_PolicyDenied` (-65570) was observed; permission denial is a possibility, not a proven diagnosis. Mac, Sender and extension all declare `_caparc-demo._tcp`, matching the sender configuration.

[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) explains that incoming TCP does not require the Local Network privilege while Bonjour does, and that the simulator cannot verify iOS Local Network privacy. The two paths must therefore be verified independently. No privacy state, firewall, VPN, network route or system protection was changed.

Native app accessibility calls repeatedly stalled and required interruption, including after normal launch; existing Chrome inspection worked and showed App Store Connect still at sign-in. Physical device access was locked at the last successful status read; later bounded device reads timed out. Consequently real Share-extension interaction, physical receipt/ACK and Finder drag remain unverified. Direct authenticated host-address connectivity was not used to bypass discovery. The evidence does not establish a production Bonjour regression, nor does it clear the release gate.

The QA receiver was stopped and its temporary pairing file removed. No new upload, draft selection, App Review submission, declaration or release-setting change occurred in this follow-up. Builds Mac 1.2 (5) and Sender 1.0 (2) remain the already delivered candidates.
