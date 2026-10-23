#!/usr/bin/env bash
# Builds, signs (Developer ID), notarizes and packages the direct-sale Mac app as a DMG.
# Needs the Apple Developer Program: see docs/RELEASE.md for the one-time setup.
#
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=permylast-notary scripts/release.sh
#
# Optional: SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" if you have several.
set -euo pipefail
: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team id (10 characters)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to the notarytool keychain profile name}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="$root/dist"
rm -rf "$out"; mkdir -p "$out"

echo "== Checks before building"
scripts/check-secrets.sh
(cd Packages/PerMyLastCore && swift test 2>&1 | tail -1)
(cd backend && npm test --silent 2>&1 | grep -E "Tests " || true)
grep -n "releaseDate\|paymentsLiveInRelease\|backendURLString =" App/PerMyLast/AppConfig.swift | sed 's/^/   config: /'
echo "   (check the release date, payments flag and backend URL above are what you intend)"

echo "== Archive and sign with: $IDENTITY"
xcodebuild -project App/PerMyLast.xcodeproj -scheme PerMyLast -configuration Release \
  -archivePath "$out/PerMyLast.xcarchive" archive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO | tail -3
app="$out/PerMyLast.xcarchive/Products/Applications/Per My Last.app"

echo "== Verify the signature"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv --verbose=2 "$app" 2>&1 | grep -E "Authority=Developer ID Application|TeamIdentifier|flags=" 
codesign -dv "$app" 2>&1 | grep -q "runtime" || { echo "Hardened runtime is not enabled; notarization would fail"; exit 1; }
scripts/check-secrets.sh "$app"

echo "== Notarize the app"
ditto -c -k --keepParent "$app" "$out/PerMyLast.zip"
xcrun notarytool submit "$out/PerMyLast.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
rm "$out/PerMyLast.zip"

echo "== Build, sign and notarize the DMG"
version="$(defaults read "$app/Contents/Info" CFBundleShortVersionString)"
dmg="$out/PerMyLast-$version.dmg"
stage="$(mktemp -d)"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Per My Last" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$stage"
codesign --sign "$IDENTITY" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"

echo "== Gatekeeper check (what a customer's Mac will do)"
spctl --assess --type execute --verbose=2 "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
shasum -a 256 "$dmg"
echo "Done: $dmg"
