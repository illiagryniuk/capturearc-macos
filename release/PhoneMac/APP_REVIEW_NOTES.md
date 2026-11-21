# App Review notes — prepared for both records

CaptureArc Sender is a separate iPhone companion to CaptureArc for Mac (Apple ID 6789554439). No login, paid account, or subscription is needed. The iPhone app sends user-selected content directly to a Mac; no developer server participates.

## Equipment and setup
Use an iPhone running iOS 17+ and a Mac running macOS 13+, connected to the same Wi-Fi network without client isolation. The Mac must be awake and running CaptureArc 1.2 or later.

1. On the Mac, open CaptureArc. A first-time user can choose **Set Up iPhone Sharing** without authorizing a screenshot folder. Open **From iPhone → Pair iPhone**.
2. Open **CaptureArc Sender** on iPhone, choose **Scan Mac QR Code**, and scan the Mac QR. Allow Camera for scanning and Local Network for direct transfer. Manual code entry is available without Camera access.
3. Enter a short synthetic message in Sender and choose **Send to Mac**. Sender confirms success only after the Mac receives and stores the item. The Mac's clipboard now contains that text.
4. In Photos, select one or more small images → Share → More → **CaptureArc**. The Mac displays photo cards; drag a card into another app. Originals remain on iPhone.
5. In Safari, use Share → CaptureArc to send a web link. For selected text, use the text selection menu. Notes' top Share button intentionally shares the whole note; select/copy and paste into Sender if the source app does not expose selection sharing.
6. On Mac, **Stop Receiving** revokes that pairing. A new pairing uses a new secret. Closing the app pauses reception; reopening resumes a saved pairing. The phone's **Forget Mac** clears its saved pairing.

Up to five items per share; text up to 1 MiB, each photo/file up to 10 MiB, twenty received cards on Mac. At capacity, remove cards and retry. All payloads are transferred over Apple's Network/Security TLS APIs with a randomly generated shared key. No account creation/deletion flow is applicable.

## Mac's existing capture feature
Authorize only a disposable capture folder in setup. Choose that same folder in Shift–Command–5 → Options → Save to. CaptureArc observes saved captures; it does not capture the screen or require Screen Recording, Accessibility, or Full Disk Access. The Files tab can keep user-authorized folders in persistent tabs.

## Submission order
Submit/release the Mac update before submitting the iPhone companion so the review team and users can obtain the required Mac 1.2 publicly. Keep manual release selected on both records. Do not provide a real pairing QR, secret, or personal content in review attachments. Add verified review contact details in App Store Connect after sign-in.
