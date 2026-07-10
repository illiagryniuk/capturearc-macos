# Manual submission checklist

## Account and contracts

- [x] Updated Apple Developer Program License Agreement accepted by Account Holder
- [x] Digital Services Act trader status completed accurately
- [x] Legal entity details current in the active developer account
- [x] Free Apps Agreement active
- [ ] Paid Apps Agreement active if pricing or in-app purchases require it
- [ ] Banking and tax forms complete if the app is paid

Paid-app agreements, banking, and tax setup are not required for the current free app with no in-app purchases.

## App identity and signing

- [x] Final name reserved: `CaptureArc: Screenshot Shelf`
- [x] Explicit App ID exists: `com.illiagryniuk.capturearc`
- [x] Mac App Distribution certificate installed
- [x] Mac Installer Distribution certificate installed
- [x] Mac App Store provisioning profile matches bundle ID and team
- [x] Version/build are newer than every uploaded build
- [x] Final `.pkg` passes local signature and package validation
- [x] Universal binary still contains both arm64 and x86_64 slices
- [x] Final `.pkg` passes Apple's upload validation as build 1.0.0 (2)
- [x] Processed build 1.0.0 (2) attached to macOS version 1.0

## Store listing

- [x] Subtitle, description, keywords, categories, age rating, and copyright entered
- [x] Public Privacy Policy URL works without sign-in
- [x] Public Support URL works without sign-in
- [x] App privacy answer is “Data Not Collected” and still matches the binary
- [x] Saved “Data Not Collected” privacy disclosure published
- [x] Export compliance answer matches the binary
- [x] Content-rights answer completed
- [x] Five 2880×1800 screenshots uploaded and verified in order
- [x] App Review contact name, email, and phone entered
- [x] Review notes entered; no demo account required

## Product decisions

- [x] Price confirmed: free (USD 0.00 across all 175 price regions)
- [x] Territories confirmed: all 175 countries and regions
- [x] Automatic, manual, or scheduled release confirmed: manual
- [x] Phased release decision confirmed: not enabled for the initial manual release
- [x] macOS minimum version confirmed as 13.0
- [ ] Support ownership confirmed

## Final QA

- [x] Clean first launch shows the authorization onboarding
- [x] Folder authorization works in sandbox
- [x] New screenshot appears and animates immediately toward the notch
- [x] Authorization persists after quit/relaunch
- [x] Drag, Share, Copy, Reveal, Quick Look, and Trash tested
- [ ] Launch at Login tested in the distribution-signed build
- [ ] Notch and no-notch display behavior tested
- [ ] Reduced Motion behavior tested
- [x] No unexpected permission prompts or network calls
- [ ] Internal/TestFlight build tested on a second Mac/user account

## Human release gate

- [ ] Owner manually approves **Add for Review**
- [ ] Owner manually approves **Submit for Review**
