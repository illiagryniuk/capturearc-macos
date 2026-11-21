# Screenshot handoff

- iPhone upload files: `iPhone/01-pair-your-mac.jpg` and `iPhone/02-ready-to-send.jpg`, **1206 × 2622**, RGB with no alpha. Captured from the actual app on the dedicated iPhone 17 Pro simulator using Simulator's Save Screen control. PNG originals are retained as source captures only; upload the JPGs.
- Mac upload file: `Mac/06-from-iphone-cards.png`, **2880 × 1800**, RGB with no alpha. The card view is an authentic native capture of the signed sandboxed release QA app using synthetic text, an owned CaptureArc brand image as a photo fixture, and example.com. The surrounding captions/background use the repository's native AppKit asset pipeline. No real user's content or live QR is shown.
- The Mac's five existing screenshots in `release/AppStore/screenshots` can be retained after reviewing their existing-feature claims. Use the new sharing screenshot first for the 1.2 update if desired.

The paired iPhone screenshot uses an inactive, simulator-only pairing fixture; it shows the ready-to-send state and does not claim a successful two-device transfer. The fixture was forgotten afterward. Physical first-run, Share extension, and drag/drop checks remain in the release checklist.

Regenerate the Mac composition from an authentic native screenshot:

```sh
swift script/generate_phone_mac_screenshot.swift path/to/native-card-capture.png release/PhoneMac/screenshots/Mac/06-from-iphone-cards.png
```

Screenshots have been inspected for visible personal data, pairing secrets, dimensions, alpha, and caption layout. Final marketing selection remains with the owner.
