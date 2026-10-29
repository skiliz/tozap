#!/bin/zsh
# Notarizes and staples a Developer ID-signed build, then repackages it (Apple's notarytool + stapler flow).
# One-time setup, which stores the credentials in your login keychain (never in this repository):
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <TEAMID>
# Then:  ZAP_NOTARY_PROFILE=<profile> scripts/notarize.sh
set -euo pipefail
cd "${0:A:h}/.."
: "${ZAP_NOTARY_PROFILE:?Set ZAP_NOTARY_PROFILE to a notarytool keychain profile}"

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
APP="build/ZAP Remote.app"
codesign --verify --strict --deep "$APP"
codesign -dv "$APP" 2>&1 | grep -q "(runtime)" || { echo "Not signed with the hardened runtime: build with ZAP_SIGN_IDENTITY."; exit 1; }

scripts/package.sh
xcrun notarytool submit "dist/ZAP-$VERSION.zip" --keychain-profile "$ZAP_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
scripts/package.sh                                   # repackage the stapled app
xcrun notarytool submit "dist/ZAP-$VERSION.dmg" --keychain-profile "$ZAP_NOTARY_PROFILE" --wait
xcrun stapler staple "dist/ZAP-$VERSION.dmg"
(cd dist && shasum -a 256 "ZAP-$VERSION.dmg" "ZAP-$VERSION.zip" > SHA256SUMS.txt)

# Gatekeeper must accept both, as it will on a user's Mac
xcrun stapler validate "$APP"
spctl --assess --type execute -vv "$APP"
spctl --assess --type open --context context:primary-signature -vv "dist/ZAP-$VERSION.dmg"
cat dist/SHA256SUMS.txt
