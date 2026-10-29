#!/bin/zsh
# Builds "build/ZAP Remote.app", the developer CLI (build/zapctl) and the test runner.
#   scripts/build.sh          build
#   scripts/build.sh test     build and run the tests
#   ZAP_DEVTOOLS=1 scripts/build.sh   developer build: adds the offline preview, the menu bar demo and the
#                                     zapremote:// automation hooks, which the public app does not contain
# Plain swiftc on purpose: it works with just the Command Line Tools (no Xcode project, no SwiftPM).
set -euo pipefail
cd "${0:A:h}/.."

SDK=$(xcrun --show-sdk-path)
FLAGS=(-O -swift-version 5 -target arm64-apple-macos14.0 -sdk "$SDK")
OUT=${ZAP_BUILD_DIR:-build}  # developer builds can go elsewhere, e.g. ZAP_BUILD_DIR=build-dev
OBJ=$OUT/obj
APP="$OUT/ZAP Remote.app"
mkdir -p $OBJ

echo "• ZAPKit"
swiftc $FLAGS -parse-as-library -emit-library -static -emit-module -module-name ZAPKit \
  -emit-module-path $OBJ/ZAPKit.swiftmodule -o $OBJ/libZAPKit.a Sources/ZAPKit/*.swift

echo "• tests"
swiftc $FLAGS -I $OBJ -L $OBJ -lZAPKit Tests/main.swift -o $OUT/zap-tests
if [[ "${1:-}" == "test" ]]; then
  $OUT/zap-tests
fi

echo "• zapctl"
swiftc $FLAGS -I $OBJ -L $OBJ -lZAPKit Sources/zapctl/main.swift -o $OUT/zapctl

echo "• ZAP Remote.app${ZAP_DEVTOOLS:+ (developer tools)}"
APP_FLAGS=()
[[ -n "${ZAP_DEVTOOLS:-}" ]] && APP_FLAGS=(-D ZAP_DEVTOOLS)
swiftc $FLAGS $APP_FLAGS -parse-as-library -I $OBJ -L $OBJ -lZAPKit Sources/ZAP/*.swift -o $OBJ/ZAP

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp $OBJ/ZAP "$APP/Contents/MacOS/ZAP"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${ZAP_DEVTOOLS:-}" ]]; then  # the automation URL scheme exists only in developer builds
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" -c "Add :CFBundleURLTypes:0 dict" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLName string local.fireremote.app.automation" \
    -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string zapremote" \
    "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"  # About → license, acknowledgements
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

xattr -cr "$APP"  # no extended attributes (e.g. provenance) end up in the ZIP as ._ files

# Signing: always the hardened runtime with the microphone entitlement. A Developer ID identity
# (ZAP_SIGN_IDENTITY) adds a secure timestamp; without one the bundle is ad-hoc signed (docs/RELEASING.md).
if [[ -n "${ZAP_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements Resources/ZAP.entitlements \
    --sign "$ZAP_SIGN_IDENTITY" "$APP"
else
  codesign --force --options runtime --entitlements Resources/ZAP.entitlements --sign - "$APP"
fi
codesign --verify --strict "$APP"
for file in LICENSE THIRD_PARTY_NOTICES.md; do  # MIT: the license travels with every copy of the app
  [[ -f "$APP/Contents/Resources/$file" ]] || { echo "missing $file in the bundle"; exit 1; }
done
echo "built: $PWD/$APP ($(lipo -archs "$APP/Contents/MacOS/ZAP"))"
