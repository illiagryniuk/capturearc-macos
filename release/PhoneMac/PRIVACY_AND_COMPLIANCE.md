# Privacy and store questionnaire preparation

## App privacy answer
Recommended for both apps: **Data Not Collected**. No developer or third-party server receives the transferred contents, filenames, pairing secrets, addresses, identifiers, or usage analytics. Transfers go directly to the user's paired Mac. This conclusion applies Apple's definition of collection as data made accessible to the developer or integrated third-party partners beyond servicing the request; it is not a claim that data never leaves the iPhone. See [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).

The website draft explicitly describes transfer, clipboard changes, storage, deletion, and permissions. Publish it with the release. Do not retain the old claim that CaptureArc never transmits personal data.

## Local storage and permissions
- Mac: App Sandbox, network client/server, app-scoped folder bookmarks, user-selected read/write. Hardened Runtime remains enabled. Received files/text use a private app support directory with 0700 directories and 0600 files. They remain until removed in the app. Removing a card or clearing the received shelf deletes that Mac copy; iPhone originals remain. Existing capture retention continues to use Trash.
- Mac clipboard: incoming text replaces it after successful staging/persistence; photos, links, and local fixtures do not. Restoring the shelf does not overwrite the clipboard. Other apps and OS clipboard features may use copied text.
- Pairing: the active key is stored in each app's Keychain. The iPhone app and its own extension share one restricted keychain access group. Stop Receiving disables resumption and deletes the Mac secret. Forget Mac deletes the iPhone's copy. No secret appears in logs or screenshots.
- iPhone: Camera only for QR scanning; Local Network for paired Wi-Fi transfer. Item providers/file picker give access only to chosen items. No broad Photos permission, Contacts, Location, Microphone, or tracking permission is requested. Contents are not retained by Sender after sending; the source app/OS may retain its own originals or provider temporary files.
- Native diagnostic logs contain transfer-stage names and acceptance booleans only, never content, pairing codes, or peer addresses. No third-party SDKs or analytics dependencies were added.

## Privacy manifests
Mac retains its existing UserDefaults reason CA92.1 and file timestamp reason 3B52.1. The iPhone app and Share extension each include a manifest declaring no tracking, no collected data, and no required-reason API categories used by their own code. Verify Apple's merged privacy report during final store validation if build tooling flags any additional API use.

## Encryption
`ITSAppUsesNonExemptEncryption=false` is included in both apps and the extension. All cryptography is supplied by Apple's Network, Security, and CryptoKit frameworks; there is no embedded custom cryptographic implementation. Under [Apple's encryption documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption), encryption limited to the Apple OS does not require uploading export-compliance documentation to App Store Connect. The owner should confirm the questionnaire answers when submitting; this document does not certify compliance with every applicable jurisdiction.

## Age rating and account declarations
No ads, social/messaging network, public user-generated-content feed, unrestricted embedded browser, purchases, gambling, medical advice, or bundled mature content. User-selected personal files are a local productivity feature. Answer the updated questionnaire from these implemented capabilities and let App Store Connect calculate the rating. Owner/account session is required for content-rights declarations, trader status, agreements, review contact, and final territories/pricing. Do not accept legal declarations on the owner's behalf without explicit approval.

## Toolchain and screenshots
Built using Xcode 26.6 and the iOS 26.5/macOS 26.5 SDKs. Current [Apple upload requirements](https://developer.apple.com/news/upcoming-requirements/) require Xcode 26+ for iOS uploads from April 28, 2026; this candidate meets that toolchain threshold. Minimum deployment targets remain iOS 17 and macOS 13.
Use genuine synthetic-content screenshots in the dimensions listed in [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/). Do not show live pairing codes or personal content. Mac screenshots use 16:10; iPhone screenshots must match accepted device dimensions and have no alpha channel.
