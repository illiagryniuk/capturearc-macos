# Manual submission checklist

## Account and contracts

- [ ] Updated Apple Developer Program License Agreement accepted by Account Holder
- [ ] Digital Services Act trader status completed accurately
- [ ] Legal entity details current
- [ ] Free Apps Agreement active
- [ ] Paid Apps Agreement active if pricing or in-app purchases require it
- [ ] Banking and tax forms complete if the app is paid

## App identity and signing

- [ ] Final name reserved: `CaptureArc: Screenshot Shelf`
- [ ] Explicit App ID exists: `com.illiagryniuk.capturearc`
- [ ] Apple Distribution certificate installed
- [ ] Mac Installer Distribution certificate installed
- [ ] Mac App Store provisioning profile matches bundle ID and team
- [ ] Version/build are newer than every uploaded build
- [ ] Final `.pkg` passes signature and package validation
- [ ] Universal binary still contains both arm64 and x86_64 slices

## Store listing

- [ ] Subtitle, description, keywords, categories, age rating, and copyright entered
- [ ] Public Privacy Policy URL works without sign-in
- [ ] Public Support URL works without sign-in
- [ ] App privacy answer is “Data Not Collected” and still matches the binary
- [ ] Export compliance answer matches the binary
- [ ] Content-rights answer completed
- [ ] At least one 2880×1800 screenshot uploaded; first three verified in order
- [ ] App Review contact name, email, and phone entered
- [ ] Review notes entered; no demo account required

## Product decisions

- [ ] Price confirmed
- [ ] Territories confirmed
- [ ] Automatic, manual, or scheduled release confirmed
- [ ] Phased release decision confirmed
- [ ] macOS minimum version confirmed as 13.0
- [ ] Support ownership confirmed

## Final QA

- [ ] Clean first launch shows the authorization onboarding
- [ ] Folder authorization works in sandbox
- [ ] New screenshot appears and animates immediately toward the notch
- [ ] Authorization persists after quit/relaunch
- [ ] Drag, Share, Copy, Reveal, Quick Look, and Trash tested
- [ ] Launch at Login tested in the distribution-signed build
- [ ] Notch and no-notch display behavior tested
- [ ] Reduced Motion behavior tested
- [ ] No unexpected permission prompts or network calls
- [ ] Internal/TestFlight build tested on a second Mac/user account

## Human release gate

- [ ] Owner manually approves **Add for Review**
- [ ] Owner manually approves **Submit for Review**
