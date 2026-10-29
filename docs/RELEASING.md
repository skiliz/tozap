# Releasing ZAP

Releases are built locally on an Apple silicon Mac; CI only builds and tests. A release is published only
when it is signed with a Developer ID, notarized by Apple and accepted by Gatekeeper. The scripts enforce
this and refuse anything else.

## One-time prerequisites

1. **Apple Developer Program membership** for the publisher. An organisation account needs a legal entity
   with a D-U-N-S number, and its legal name appears in the certificate.
2. A **Developer ID Application** certificate in the login keychain. `security find-identity -v -p codesigning`
   should list it.
3. A **notarytool keychain profile**, which stores the credentials in the keychain and never in this
   repository:
   ```sh
   xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id <TEAMID>
   ```
4. A **bundle identifier** on a domain the publisher controls, to replace `local.fireremote.app` in
   `Resources/Info.plist` before the first signed build. The change resets the macOS permissions
   (microphone, speech, local network) once. Preferences are stored under the bundle identifier, so they
   need a one-time migration.
5. The **GitHub CLI** (`gh`), logged in as a maintainer of `skiliz/zap`, and a clone of `skiliz/homebrew-tap`
   next to this repository (or set `ZAP_TAP_DIR`).

Before the first signed release, also move the pairing token to the Keychain. A stable Developer ID
signature makes that prompt-free.

## Steps

1. Set `CFBundleShortVersionString` (and increment `CFBundleVersion`) in `Resources/Info.plist`.
2. Add the version's section to `CHANGELOG.md`; it becomes the release notes. Replace "Unreleased" with the
   date.
3. Commit to `main` and push.
4. Run:
   ```sh
   ZAP_SIGN_IDENTITY="Developer ID Application: <legal name> (<TEAMID>)" \
   ZAP_NOTARY_PROFILE=<profile> scripts/release.sh
   ```
   `scripts/release.sh` does the following:
   1. Refuses developer builds.
   2. Builds with the hardened runtime and `Resources/ZAP.entitlements`, and runs the tests.
   3. Packages, notarizes and staples the app and the DMG with `scripts/notarize.sh`, then checks them with
      `spctl`.
   4. Writes `dist/SHA256SUMS.txt`.
   5. Tags `v<version>` and creates a **draft** GitHub Release with the DMG, the ZIP and the checksums.
   6. Writes `Casks/zap-remote.rb` in the tap from `templates/zap-remote.rb.in`, with the real version and the
      ZIP's SHA-256.
5. Check the draft release's assets and checksums on GitHub, then publish it.
6. In the tap, run `brew style Casks/zap-remote.rb` and
   `brew audit --cask --strict --online skiliz/tap/zap-remote`. Then commit and push.
7. On a clean Mac or user account, test `brew install --cask skiliz/tap/zap-remote`:
   - first launch with Gatekeeper on;
   - pairing;
   - `brew upgrade` keeps the pairing;
   - `brew uninstall --cask zap-remote`, and `--zap` removes `~/Library/Application Support/ZAP Remote`.

Never commit signing certificates, passwords, API keys or tokens. Signing credentials come from the local
keychain and environment only.

## Developer builds

`ZAP_DEVTOOLS=1 scripts/build.sh` adds an offline UI preview, a menu bar demo and the `zapremote://`
automation interface (see CONTRIBUTING.md). `scripts/package.sh`, `scripts/release.sh` and CI refuse such
builds.
