#!/bin/zsh
# Packages "build/ZAP Remote.app" into dist/ZAP-<version>.dmg, dist/ZAP-<version>.zip and dist/SHA256SUMS.txt.
# Run scripts/build.sh first.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
APP="build/ZAP Remote.app"
[[ -d "$APP" ]] || { echo "Build first: scripts/build.sh"; exit 1; }
codesign --verify --strict "$APP"
# Never package a developer build: it contains the automation hooks (ZAP_DEVTOOLS).
if /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$APP/Contents/Info.plist" >/dev/null 2>&1 \
   || otool -L "$APP/Contents/MacOS/ZAP" | grep -q ScreenCaptureKit \
   || strings "$APP/Contents/MacOS/ZAP" | grep -q "automation is off"; then
  echo "This is a developer build (ZAP_DEVTOOLS). Rebuild with scripts/build.sh before packaging."
  exit 1
fi

DIST=dist
rm -rf $DIST
mkdir -p $DIST

# DMG: the app next to an Applications link, for drag-to-install
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/ZAP Remote.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "ZAP $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DIST/ZAP-$VERSION.dmg"
rm -rf "$STAGE"

# ZIP: used by the Homebrew cask
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/ZAP-$VERSION.zip"

(cd $DIST && shasum -a 256 "ZAP-$VERSION.dmg" "ZAP-$VERSION.zip" > SHA256SUMS.txt)
cat $DIST/SHA256SUMS.txt
