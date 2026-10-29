# Contributing to to.zap

Thanks for helping! to.zap aims to stay a small, native, dependable Mac utility, so please keep changes
focused.

## Reporting issues

Open an issue with your macOS version, Mac model (Apple silicon / Intel), Fire TV model and Fire OS
version (Settings → My Fire TV → About), what you did, and what happened. **Never post your TV's IP
address, pairing token, serial number or screenshots showing them.** Security problems: see
[SECURITY.md](SECURITY.md).

Reports from Fire TV models other than the verified one are especially welcome — please say which
features worked, so [COMPATIBILITY.md](COMPATIBILITY.md) can grow from real results.

## Building

Requirements: macOS 14 or later on Apple silicon, and Xcode or just the Command Line Tools
(`xcode-select --install`). There are no package dependencies.

```sh
scripts/build.sh test      # builds build/to.zap.app, build/zapctl, runs the tests
open "build/to.zap.app"
```

The build uses `swiftc` directly so it works without an Xcode project. The app avoids `@State` because
the Command Line Tools don't ship SwiftUI's macro plugin; keep view state in the `@Observable` models.

`build/zapctl` is a developer CLI over the same `ZAPKit` code (`zapctl status`, `apps`, `discover`,
`parse "<frase>"`…). Commands that act on the TV should only be run with someone watching it.

## Pull requests

- One change per pull request, with a clear description and how you tested it.
- Run `scripts/build.sh test` before submitting; CI runs the same.
- Don't add third-party dependencies, telemetry or network calls to anything other than the user's TV (the
  only exceptions are the documented, optional app-icon downloads, the user-chosen Alexa mode and the
  user-initiated Check for Updates).
- Never weaken TLS verification or pairing.
- Only describe features as working if you verified them on a real device, and say which one.
- Write documentation in clear, concise English.

By contributing you agree that your contribution is licensed under the MIT License of this project.

## Developer builds

`ZAP_DEVTOOLS=1 scripts/build.sh` builds a developer version that adds:

- an offline UI preview that never contacts the TV or the network:
  `open -n "build/to.zap.app" --args -ZAPOfflinePreview YES`, plus `-ZAPSettingsSection about` to open a
  Settings section and `-ZAPMenuBarDemo YES` to cycle the menu bar light through its states;
- `-ZAPSettingsSection <section> -ZAPCaptureSettings <file.png>` opens a Settings section, captures to.zap's own
  window (no Screen Recording permission needed) and quits; used for the README screenshots. Add
  `-ZAPCaptureSize 820x660` (the default window size) for a known size; the remembered window position is left alone;
- a `zapremote://` automation interface for testing (see `RemoteModel.handleURL`). It is enabled only by
  `defaults write local.tozap.app automationURLs -bool true`; turn it off with
  `defaults delete local.tozap.app automationURLs`.

None of this is compiled into release builds, and `scripts/package.sh` refuses to package a developer build.
