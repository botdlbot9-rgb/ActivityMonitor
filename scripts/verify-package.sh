#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.10.0}"
APP='dist/Activity Monitor.app'
for ARCH in arm64 x86_64; do
  lipo "$APP/Contents/MacOS/ActivityMonitor" -verify_arch "$ARCH"
done
codesign --verify --deep --strict "$APP"
[[ -s "$APP/Contents/Resources/Sparkle-LICENSE.txt" ]]
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
[[ -L "$SPARKLE/Versions/Current" && -x "$SPARKLE/Autoupdate" && -d "$SPARKLE/Updater.app" ]]
lipo "$SPARKLE/Sparkle" -verify_arch arm64 x86_64
otool -L "$APP/Contents/MacOS/ActivityMonitor" | grep -F '@rpath/Sparkle.framework/'
otool -l "$APP/Contents/MacOS/ActivityMonitor" | grep -F '@executable_path/../Frameworks'
[[ "$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$APP/Contents/Info.plist")" == 'https://github.com/wieslawsoltes/ActivityMonitor/releases/latest/download/appcast.xml' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")" == 'LSbDjvx0CrpFJpSBbNtUeB9JqgqrHzAjeF6NbgtwGAk=' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print SUVerifyUpdateBeforeExtraction' "$APP/Contents/Info.plist")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print SURequireSignedFeed' "$APP/Contents/Info.plist")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")" == "$VERSION" ]]
(cd dist && shasum -a 256 -c SHA256SUMS)
hdiutil verify "dist/ActivityMonitor-$VERSION-universal.dmg"
STAGE="$(mktemp -d)"
MOUNT="$STAGE/mount"
cleanup() {
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  rm -rf "$STAGE"
}
trap cleanup EXIT
hdiutil attach "dist/ActivityMonitor-$VERSION-universal.dmg" -readonly -nobrowse -mountpoint "$MOUNT"
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]]
cmp dist/INSTALL.md "$MOUNT/Read Me.txt"
codesign --verify --deep --strict "$MOUNT/Activity Monitor.app"
cmp "$APP/Contents/MacOS/ActivityMonitor" "$MOUNT/Activity Monitor.app/Contents/MacOS/ActivityMonitor"
ditto -x -k "dist/ActivityMonitor-$VERSION-universal.zip" "$STAGE/zip"
codesign --verify --deep --strict "$STAGE/zip/Activity Monitor.app"
cmp "$APP/Contents/MacOS/ActivityMonitor" "$STAGE/zip/Activity Monitor.app/Contents/MacOS/ActivityMonitor"
if [[ "${EXPECT_NOTARIZED:-0}" == 1 ]]; then
  for SIGNED_APP in "$APP" "$MOUNT/Activity Monitor.app" "$STAGE/zip/Activity Monitor.app"; do
    xcrun stapler validate "$SIGNED_APP"
    spctl --assess --type execute --verbose=2 "$SIGNED_APP"
  done
  xcrun stapler validate "dist/ActivityMonitor-$VERSION-universal.dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "dist/ActivityMonitor-$VERSION-universal.dmg"
fi
echo 'Universal app, DMG, ZIP, version and checksums verified.'
