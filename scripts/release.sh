#!/bin/sh
# Builds a release zip of FreeTheNotch for GitHub Releases.
#
# The app is archived unsigned, then signed with a local self-signed code-signing
# identity, so the published binary carries no Apple ID. Keeping the same identity
# across releases keeps the designated requirement stable, so macOS keeps the
# permissions users granted when they update.
#
# Usage: scripts/release.sh
#   FTN_SIGNING_IDENTITY  certificate name (default "FreeTheNotch Release"; "-" for an ad-hoc test build)

set -eu

IDENTITY="${FTN_SIGNING_IDENTITY:-FreeTheNotch Release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/build/release"
ARCHIVE="$OUTPUT/FreeTheNotch.xcarchive"

fail() {
    echo "error: $*" >&2
    exit 1
}

if [ "$IDENTITY" != "-" ]; then
    security find-identity -p codesigning | grep -q "\"$IDENTITY\"" ||
        fail "no code-signing identity named \"$IDENTITY\" in the keychain (Keychain Access → Certificate Assistant → Create a Certificate…, type Code Signing)"
fi

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

echo "==> Archiving Release build"
xcodebuild -project "$ROOT/FreeTheNotch.xcodeproj" -scheme FreeTheNotch -configuration Release \
    -archivePath "$ARCHIVE" archive CODE_SIGNING_ALLOWED=NO -quiet

APP="$(find "$ARCHIVE/Products" -maxdepth 3 -name FreeTheNotch.app -type d | head -n 1)"
[ -n "$APP" ] || fail "FreeTheNotch.app not found in $ARCHIVE"

echo "==> Signing with \"$IDENTITY\""
# Nested code first, then the app with its entitlements and the hardened runtime.
find "$APP/Contents" -name '*.dylib' -type f | while read -r library; do
    codesign --force --timestamp=none --sign "$IDENTITY" "$library"
done
codesign --force --timestamp=none --options runtime \
    --entitlements "$ROOT/FreeTheNotch.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP" || fail "signature does not verify"

echo "==> Checking for personal data"
if grep -rlaF "/Users/$(id -un)/" "$APP" >/dev/null; then
    grep -rlaF "/Users/$(id -un)/" "$APP" >&2
    fail "the app contains paths from this Mac"
fi
if codesign -dvv "$APP" 2>&1 | grep '^Authority=' | grep -q '@'; then
    fail "the signing certificate contains an email address"
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
ZIP="$OUTPUT/FreeTheNotch-$VERSION.zip"

echo "==> Packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$ZIP")" >"$(basename "$ZIP").sha256")

echo
echo "Version $VERSION (build-$BUILD)"
echo "App:     $APP"
echo "Zip:     $ZIP"
echo "SHA-256: $(cut -d ' ' -f 1 "$ZIP.sha256")"
