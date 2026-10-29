# Releasing to.zap

Releases are built locally on an Apple silicon Mac; CI only builds and tests. Both modes sign with the hardened
runtime. `scripts/release.sh` has two modes:

| Mode | Signature | Notarized | What users see |
|---|---|---|---|
| `ZAP_RELEASE_MODE=adhoc` (current) | Ad-hoc (`codesign -s -`) | No | macOS blocks the first launch; the user approves it once in System Settings → Privacy & Security → **Open Anyway**, and again after each update |
| Developer ID (default mode of the script) | Developer ID Application | Yes, stapled | Opens normally |

to.zap is currently released in **ad-hoc mode**, because the project has no paid Apple Developer Program
membership. Never describe an ad-hoc release as signed, notarized or "verified by Apple", never strip the
quarantine attribute (in scripts, the cask or the docs), and never suggest turning off Gatekeeper.

## One-time prerequisites

Both modes:

1. The **GitHub CLI** (`gh`), logged in as a maintainer of `skiliz/tozap`, and a clone of `skiliz/homebrew-tap`
   next to this repository (or set `ZAP_TAP_DIR`). Run the release from a fresh clone of `skiliz/tozap` on `main`.
2. The bundle identifier is **`local.tozap.app`** (`Resources/Info.plist`, the logging subsystem, the
   preferences path in the cask's `zap trash:`). Never change it again: macOS keys permissions, preferences and
   the login item to it. Pre-release builds used `local.zap.app` and `local.fireremote.app`; their settings and the
   Settings window position move across once (`PreferencesMigration`), and any other legacy keys are dropped. Their
   pairing data moves from `~/Library/Application Support/ZAP Remote` (or `ZAP`) to `to.zap` (`PairingStore`).

Developer ID mode only:

3. **Apple Developer Program membership** for the publisher (an organisation needs a D-U-N-S number), and a
   **Developer ID Application** certificate in the login keychain (`security find-identity -v -p codesigning`).
4. A **notarytool keychain profile**, which keeps the credentials in the keychain and never in this repository:
   `xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id <TEAMID>`.
5. Then move the pairing token to the Keychain: a stable signature makes that prompt-free.

## Steps

1. Set `CFBundleShortVersionString` (and increment `CFBundleVersion`) in `Resources/Info.plist`.
2. Add the version's section to `CHANGELOG.md` with its date; it becomes the release notes.
3. Commit to `main` and push.
4. Run `ZAP_RELEASE_MODE=adhoc scripts/release.sh` (or, with a Developer ID,
   `ZAP_SIGN_IDENTITY="Developer ID Application: <legal name> (<TEAMID>)" ZAP_NOTARY_PROFILE=<profile> scripts/release.sh`).
   To publish an artifact that was already built from the same source and tested on a clean account, add
   `ZAP_RELEASE_DIST=<folder with tozap-<version>.zip, .dmg and SHA256SUMS.txt>`: the script verifies it and uploads
   those exact files instead of rebuilding (a rebuilt ZIP would have a different SHA-256). Commits after the
   artifact was built may only touch files outside the app bundle (such as dating CHANGELOG.md): the script
   rebuilds the tagged source and requires the identical app bundle. Pass an absolute path. The script:
   1. refuses developer builds, a dirty tree, an existing tag or a missing dated changelog entry;
   2. builds arm64 and runs the tests;
   3. ad-hoc mode: checks the ad-hoc signature and packages; Developer ID mode: packages, notarizes, staples
      and checks Gatekeeper with `scripts/notarize.sh`;
   4. writes `dist/SHA256SUMS.txt`;
   5. tags `v<version>` and creates a **draft** GitHub Release with the DMG, the ZIP and the checksums. In
      ad-hoc mode the notes start with the "not notarized, Open Anyway" notice;
   6. writes `Casks/tozap-remote.rb` in the tap from `templates/tozap-remote-adhoc.rb.in` (with caveats) or
      `templates/tozap-remote.rb.in`, with the real version and the ZIP's SHA-256, and fails if a placeholder is
      left.
5. On a clean macOS user account, download the draft's ZIP in a browser (so it is quarantined) and check:
   - the SHA-256 matches `SHA256SUMS.txt`;
   - ad-hoc mode: the first launch is blocked, **Open Anyway** in System Settings → Privacy & Security works,
     and nothing else is needed;
   - pairing, the remote, voice permissions and Check for Updates.
6. Publish the release on GitHub.
7. In the tap: `brew audit --cask --strict --online skiliz/tap/tozap-remote` (not `--new`, which requires
   notarization), commit and push.
8. Test Homebrew on a clean account:
   - `brew install --cask skiliz/tap/tozap-remote`: the same Gatekeeper approval appears, and the caveats explain it;
   - `brew upgrade --cask skiliz/tap/tozap-remote` keeps the pairing. In ad-hoc mode Homebrew warns that the signer
     changed, macOS asks for approval again and may ask again for Microphone, Speech Recognition and Local
     Network; check that the login item still works;
   - `brew uninstall --cask tozap-remote` keeps the data, and `--zap` removes `~/Library/Application Support/to.zap` and `~/Library/Preferences/local.tozap.app.plist`.

Never commit signing certificates, passwords, API keys or tokens. Signing credentials come from the local
keychain and environment only. Never attach third-party binaries (such as the mirroring receiver's APK) to a
release.

## Developer builds

`ZAP_DEVTOOLS=1 scripts/build.sh` adds an offline UI preview, a menu bar demo, screenshot capture and the
`zapremote://` automation interface (see CONTRIBUTING.md); `ZAP_BUILD_DIR=build-dev` keeps it apart from the
normal build. `scripts/package.sh`, `scripts/release.sh` and CI refuse such builds.
