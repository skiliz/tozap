#!/bin/zsh
# Builds, tests, signs (Developer ID), notarizes and packages the version in Resources/Info.plist, creates a
# draft GitHub Release with the DMG, ZIP and SHA256SUMS.txt, and writes the Homebrew cask from the tap's
# template. Requires: a Developer ID Application identity (ZAP_SIGN_IDENTITY), a notarytool keychain profile
# (ZAP_NOTARY_PROFILE), the GitHub CLI logged in as a maintainer, and a clean main branch.
# See docs/RELEASING.md. It refuses to release anything that isn't signed, notarized and accepted by Gatekeeper.
set -euo pipefail
cd "${0:A:h}/.."

: "${ZAP_SIGN_IDENTITY:?Set ZAP_SIGN_IDENTITY to your Developer ID Application identity}"
: "${ZAP_NOTARY_PROFILE:?Set ZAP_NOTARY_PROFILE to a notarytool keychain profile}"
[[ -z "${ZAP_DEVTOOLS:-}" ]] || { echo "Unset ZAP_DEVTOOLS: releases never contain the developer tools."; exit 1; }
[[ "$ZAP_SIGN_IDENTITY" == "Developer ID Application:"* ]] \
  || { echo "ZAP_SIGN_IDENTITY must be a Developer ID Application identity."; exit 1; }

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
TAG="v$VERSION"
TAP="${ZAP_TAP_DIR:-../homebrew-tap}"

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first."; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "$TAG already exists."; exit 1; }
grep -q "## \[$VERSION\]" CHANGELOG.md || { echo "Add a CHANGELOG.md entry for $VERSION first."; exit 1; }
[[ -f "$TAP/templates/zap-remote.rb.in" ]] || { echo "Homebrew tap template not found in $TAP."; exit 1; }

scripts/build.sh test
scripts/notarize.sh   # packages, notarizes, staples and checks Gatekeeper

NOTES=$(mktemp)
awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {on=1; next} /^## \[/ {on=0} on' CHANGELOG.md > "$NOTES"

git tag -a "$TAG" -m "ZAP $VERSION"
git push origin "$TAG"
gh release create "$TAG" "dist/ZAP-$VERSION.dmg" "dist/ZAP-$VERSION.zip" dist/SHA256SUMS.txt \
  --title "ZAP $VERSION" --notes-file "$NOTES" --draft
rm "$NOTES"

ZIP_SHA=$(shasum -a 256 "dist/ZAP-$VERSION.zip" | awk '{print $1}')
mkdir -p "$TAP/Casks"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$ZIP_SHA/" "$TAP/templates/zap-remote.rb.in" > "$TAP/Casks/zap-remote.rb"
cat <<NEXT

Draft release $TAG created: check its assets on GitHub, then publish it.
Wrote $TAP/Casks/zap-remote.rb (version $VERSION, sha256 $ZIP_SHA). Once the release is public:
  brew style "$TAP/Casks/zap-remote.rb"
  brew audit --cask --strict --online skiliz/tap/zap-remote
then commit and push the tap, and test: brew install --cask skiliz/tap/zap-remote
NEXT
