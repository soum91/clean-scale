# Clean Scale

A minimal iOS app that connects to a Bluetooth Low Energy body scale
(OKOK/Lefu and compatible), reads your weight live, and keeps a short history.
No ads, no accounts, no network calls. You own the scale; this just talks to it.

## No Mac needed to build

Every push builds an **unsigned IPA** on GitHub's macOS runners and uploads it
as a downloadable artifact. You never open Xcode.

- Push to this repo (or hit **Actions → Build unsigned IPA → Run workflow**).
- When the run finishes, grab `CleanScale-<version>-build-<N>.ipa` from the
  [latest release](../../releases/latest). Each release lists what changed since
  the previous build, and the build number is stamped into the app (CFBundleVersion).

## Installing the IPA

An unsigned IPA still has to be signed with your own Apple ID before iOS will
run it. That's Apple's rule, not this app's. Use either:

- **AltStore** or **SideStore** — point it at the IPA, it signs with your free
  Apple ID and installs over Wi-Fi.
- **Sideloadly** — plug the phone into a computer once, drop in the IPA, enter
  your Apple ID.

Free Apple ID signing lasts 7 days, then you re-install (same as any sideloaded
app). A paid developer account stretches it to a year.

## Using it

1. Open the app, tap **Scan**, pick your scale, step on it.
2. If your scale speaks the standard Bluetooth Weight Scale Service, the weight
   shows up right away.
3. If it doesn't, tap the terminal icon (top right) to open the **raw BLE log**.
   Step on the scale, let it settle, copy the log. The weight is in those bytes.
   Send me the log and I'll fill in `decodeCustom()` in
   `Sources/BLEScaleManager.swift` for your exact model.

## Structure

- `Sources/` — the app (SwiftUI + CoreBluetooth), three files.
- `project.yml` — XcodeGen spec; CI turns this into the Xcode project.
- `.github/workflows/build.yml` — the build-and-package pipeline.

## Android alternative

If iOS isn't a hard requirement, `openScale` (open source, on F-Droid) already
supports many Lefu/OKOK scales with no building at all.
