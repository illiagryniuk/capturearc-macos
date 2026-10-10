# App Review notes

CaptureArc is a menu-bar utility that presents a shelf around the MacBook notch. It has no account, network service, advertising, analytics SDK, or in-app purchase.

## Review steps

1. Launch CaptureArc. The Welcome window opens because no capture folder has been authorized yet.
2. Choose **Authorize Capture Folder…** and create or select a test folder.
3. Press Shift–Command–5, choose **Options → Save to → Other Location…**, and select the same folder.
4. Take a screenshot with Shift–Command–3 or Shift–Command–4.
5. After macOS finishes its floating-thumbnail transition, CaptureArc immediately animates the saved file toward the notch.
6. Push the pointer into the physical notch. Moving near the colored rim alone does not open the shelf; entering the notch expands it and shows the capture.
7. Select the capture to test Share, Copy, Reveal, Quick Look, drag and drop, or Move to Trash.
8. Select **Files**, choose **Add Folder Tab…**, and authorize a folder containing test files. Confirm that folders open inside the shelf, files open in their default apps, multiple folder tabs can be selected or closed, and the tabs return after relaunch.
9. Open **CaptureArc → Settings…** to test the capture-folder selector, animation preference, retention policy, and Launch at Login.

On a Mac or display without a physical notch, CaptureArc presents the same interaction as a compact top-center pill.

## Permissions and privacy

- App Sandbox is enabled.
- The app requests read/write access only to folders chosen through the standard macOS open panel and stores an app-scoped security bookmark for each persistent folder tab.
- It does not request Screen Recording, Accessibility, Input Monitoring, camera, microphone, location, contacts, or Full Disk Access.
- It does not capture the screen. It observes finalized image and movie files in the authorized folder.
- All processing is local.

## Reviewer contact

Add the App Review contact name, phone number, and email in App Store Connect before submission. Do not put credentials here because no sign-in is required.
