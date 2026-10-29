#!/bin/zsh
# Builds, tests and packages the version in Resources/Info.plist, creates a DRAFT GitHub Release with the
# DMG, ZIP and SHA256SUMS.txt, and writes the Homebrew cask from the tap's template. Two modes:
#
#   ZAP_SIGN_IDENTITY="Developer ID Application: …" ZAP_NOTARY_PROFILE=<profile> scripts/release.sh
#       Developer ID signed, notarized, stapled and accepted by Gatekeeper (the default mode).
#   ZAP_RELEASE_MODE=adhoc scripts/release.sh
#       Ad-hoc signed, NOT notarized: users approve the app once in System Settings → Privacy & Security.
#       The release notes and the cask say so. Nothing here strips quarantine or bypasses Gatekeeper.
#   ZAP_RELEASE_DIST=<folder> (ad-hoc mode only)
#       Publishes an already built and tested dist/ (ZIP, DMG, SHA256SUMS.txt) byte for byte instead of
#       rebuilding, after checking its checksums, version, bundle identifier, signature and architecture.
#
# Both need the GitHub CLI logged in as a maintainer and a clean branch. See docs/RELEASING.md.
set -euo pipefail
cd "${0:A:h}/.."

unset ZAP_BUILD_DIR   # releases are always built, tested and packaged from build/
MODE="${ZAP_RELEASE_MODE:-developer-id}"
[[ -z "${ZAP_DEVTOOLS:-}" ]] || { echo "Unset ZAP_DEVTOOLS: releases never contain the developer tools."; exit 1; }
case "$MODE" in
  developer-id)
    : "${ZAP_SIGN_IDENTITY:?Set ZAP_SIGN_IDENTITY to your Developer ID Application identity (or ZAP_RELEASE_MODE=adhoc)}"
    : "${ZAP_NOTARY_PROFILE:?Set ZAP_NOTARY_PROFILE to a notarytool keychain profile}"
    [[ "$ZAP_SIGN_IDENTITY" == "Developer ID Application:"* ]] \
      || { echo "ZAP_SIGN_IDENTITY must be a Developer ID Application identity."; exit 1; }
    TEMPLATE=zap-remote.rb.in
    ;;
  adhoc)
    [[ -z "${ZAP_SIGN_IDENTITY:-}${ZAP_NOTARY_PROFILE:-}" ]] \
      || { echo "Ad-hoc mode: unset ZAP_SIGN_IDENTITY and ZAP_NOTARY_PROFILE (they belong to the Developer ID mode)."; exit 1; }
    TEMPLATE=zap-remote-adhoc.rb.in
    ;;
  *)
    echo "ZAP_RELEASE_MODE must be developer-id or adhoc."; exit 1 ;;
esac

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
TAG="v$VERSION"
TAP="${ZAP_TAP_DIR:-../homebrew-tap}"

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first."; exit 1; }
[[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || { echo "Release from main."; exit 1; }
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main must match origin/main: push or pull first."; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "$TAG already exists."; exit 1; }
grep -q "## \[$VERSION\] - [0-9]" CHANGELOG.md || { echo "Add a dated CHANGELOG.md entry for $VERSION first."; exit 1; }
[[ -f "$TAP/templates/$TEMPLATE" ]] || { echo "Homebrew tap template $TEMPLATE not found in $TAP."; exit 1; }
# The template must have exactly the two placeholders the script fills, checked before anything is tagged.
[[ "$(grep -o "@[A-Z0-9]*@" "$TAP/templates/$TEMPLATE" | sort -u | tr '\n' ' ')" == "@SHA256@ @VERSION@ " ]] \
  || { echo "$TEMPLATE must contain exactly @VERSION@ and @SHA256@."; exit 1; }

NOTES=$(mktemp)
if [[ -n "${ZAP_RELEASE_DIST:-}" ]]; then
  [[ "$MODE" == adhoc ]] || { echo "ZAP_RELEASE_DIST is for ad-hoc releases."; exit 1; }
  rm -rf dist && mkdir dist
  cp "$ZAP_RELEASE_DIST/ZAP-$VERSION.zip" "$ZAP_RELEASE_DIST/ZAP-$VERSION.dmg" "$ZAP_RELEASE_DIST/SHA256SUMS.txt" dist/
  (cd dist && shasum -a 256 -c SHA256SUMS.txt) || { echo "Checksums don't match."; exit 1; }
  CHECK=$(mktemp -d)
  ditto -x -k "dist/ZAP-$VERSION.zip" "$CHECK"
  APP="$CHECK/ZAP Remote.app"
  [[ "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" == "$VERSION" ]] \
    && [[ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" == "local.zap.app" ]] \
    && [[ "$(lipo -archs "$APP/Contents/MacOS/ZAP")" == "arm64" ]] \
    || { echo "The prebuilt app doesn't match version $VERSION, local.zap.app and arm64."; exit 1; }
  codesign --verify --strict --deep "$APP"
  [[ "$(codesign -dv "$APP" 2>&1)" == *"Signature=adhoc"* ]] || { echo "Expected an ad-hoc signature."; exit 1; }
  [[ "$(codesign -dv "$APP" 2>&1)" == *"(adhoc,runtime)"* ]] || { echo "Expected the hardened runtime."; exit 1; }
  [[ "$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -o 'com\.apple\.[a-z.-]*' | sort -u)" \
     == "com.apple.security.device.audio-input" ]] || { echo "Unexpected entitlements."; exit 1; }
  # The DMG must hold the same app as the ZIP.
  MOUNT=$(mktemp -d)
  hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT" "dist/ZAP-$VERSION.dmg"
  if diff -rq "$APP" "$MOUNT/ZAP Remote.app" >/dev/null; then SAME=yes; else SAME=no; fi
  hdiutil detach -quiet "$MOUNT"
  [[ "$SAME" == yes ]] || { echo "The DMG's app differs from the ZIP's."; exit 1; }
  scripts/build.sh test   # the tagged source still builds and passes its tests
  # The build is reproducible: the tagged source must produce the very binary being published.
  cmp -s "build/ZAP Remote.app/Contents/MacOS/ZAP" "$APP/Contents/MacOS/ZAP" \
    || { echo "The tagged source doesn't rebuild the published binary."; exit 1; }
  rm -rf "$CHECK"
else
  scripts/build.sh test
fi
APP="build/ZAP Remote.app"
[[ "$(lipo -archs "$APP/Contents/MacOS/ZAP")" == "arm64" ]] || { echo "Expected an arm64-only build."; exit 1; }

if [[ "$MODE" == developer-id ]]; then
  scripts/notarize.sh   # packages, notarizes, staples and checks Gatekeeper
else
  codesign --verify --strict --deep "$APP"
  [[ "$(codesign -dv "$APP" 2>&1)" == *"Signature=adhoc"* ]] || { echo "Expected an ad-hoc signature."; exit 1; }
  [[ -n "${ZAP_RELEASE_DIST:-}" ]] || scripts/package.sh
  # Informational: Gatekeeper is expected to refuse an app that isn't notarized.
  spctl --assess --type execute "$APP" 2>/dev/null && echo "note: Gatekeeper accepted the app" \
    || echo "Gatekeeper refuses the app until the user approves it, as documented."
  cat > "$NOTES" <<'UNSIGNED'
> **This release is not signed with an Apple Developer ID and not notarized by Apple.** macOS will say it
> can't verify the app. Open it once, then go to System Settings → Privacy & Security and click
> **Open Anyway** (see the README). After each update macOS asks again, and may ask again for Microphone,
> Speech Recognition and Local Network access. Check the download against `SHA256SUMS.txt`, or build from source.

UNSIGNED
fi
awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {on=1; next} /^## \[/ {on=0} on' CHANGELOG.md >> "$NOTES"

git tag -a "$TAG" -m "ZAP $VERSION"
git push origin "$TAG"
gh release create "$TAG" "dist/ZAP-$VERSION.dmg" "dist/ZAP-$VERSION.zip" dist/SHA256SUMS.txt \
  --title "ZAP $VERSION" --notes-file "$NOTES" --draft
rm "$NOTES"

ZIP_SHA=$(shasum -a 256 "dist/ZAP-$VERSION.zip" | awk '{print $1}')
mkdir -p "$TAP/Casks"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$ZIP_SHA/" "$TAP/templates/$TEMPLATE" > "$TAP/Casks/zap-remote.rb"
if grep -q "@[A-Z0-9]*@" "$TAP/Casks/zap-remote.rb"; then echo "Unfilled placeholder in the cask."; exit 1; fi
cat <<NEXT

Draft release $TAG created ($MODE): download its ZIP on a clean user account, test it as described in
docs/RELEASING.md, then publish the release.
Wrote $TAP/Casks/zap-remote.rb (version $VERSION, sha256 $ZIP_SHA). Once the release is public:
  brew audit --cask --strict --online skiliz/tap/zap-remote     (not --new: it requires notarization)
then commit and push the tap, and test: brew install --cask skiliz/tap/zap-remote
NEXT
