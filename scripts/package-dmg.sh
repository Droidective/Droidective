#!/usr/bin/env bash
# Sign the built Release app and package it into a drag-to-Applications DMG.
# Assumes the Release configuration has already been built into DerivedData.
#
# Signing identity comes from $SIGN_IDENTITY:
#   "-" (default)                ad-hoc — local dev, not notarizable.
#   "Developer ID Application…"  Developer ID — hardened runtime + secure
#                                timestamp, ready for notarization (see
#                                scripts/notarize.sh).
set -euo pipefail

VERSION="${1:-dev}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_DIR="DerivedData/Build/Products/Release"
APP="$APP_DIR/Droidective.app"
DMG="$APP_DIR/Droidective-${VERSION}.dmg"
IDENTITY="${SIGN_IDENTITY:--}"

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found — build the Release configuration first" >&2
  exit 1
fi

opts=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  opts+=(--options runtime --timestamp)
fi

# Sparkle ships nested helpers (Autoupdate, Updater.app, the Downloader/Installer
# XPC services) that xcodebuild leaves with their upstream signatures — no
# Developer ID and no secure timestamp — which notarization rejects. Re-sign each
# (preserving its entitlements), then re-seal the framework.
sparkle="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
  for version in "$sparkle"/Versions/[A-Z]; do
    [[ -d "$version" ]] || continue
    for nested in \
      "$version/XPCServices/Downloader.xpc" \
      "$version/XPCServices/Installer.xpc" \
      "$version/Autoupdate" \
      "$version/Updater.app"; do
      [[ -e "$nested" ]] && codesign "${opts[@]}" --preserve-metadata=entitlements "$nested"
    done
  done
  codesign "${opts[@]}" "$sparkle"
fi

# The bundled ffmpeg is a loose Mach-O in Resources — codesign --deep doesn't
# reliably sign those, so sign it explicitly before sealing the bundle. The
# scrcpy-server is a device-side payload, covered by the bundle seal.
ffmpeg="$APP/Contents/Resources/ffmpeg"
[[ -f "$ffmpeg" ]] && codesign "${opts[@]}" "$ffmpeg"

codesign "${opts[@]}" "$APP"
codesign --verify --deep --strict "$APP"

# Lay out a styled "drag to Applications" DMG. The window background and icon
# positions live in a Finder-authored .DS_Store committed in dmg-assets (see
# scripts/dmg-assets/README.md for how it's regenerated). We assemble the volume
# with hdiutil — no Finder/AppleScript — so it works on a headless CI runner.
# The .DS_Store's background alias is keyed to volume name "Droidective" and
# .background/background@2x.png, so both must match exactly.
assets="$(cd "$(dirname "$0")/dmg-assets" && pwd)"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$APP" "$staging/"
ln -s /Applications "$staging/Applications"
mkdir "$staging/.background"
cp "$assets/background@2x.png" "$staging/.background/background@2x.png"
cp "$assets/DS_Store" "$staging/.DS_Store"

rm -f "$DMG"
hdiutil create -volname "Droidective" -srcfolder "$staging" -ov -format UDZO "$DMG"

# Sign the DMG itself so the download carries a Developer ID signature too.
if [[ "$IDENTITY" != "-" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

echo "created $DMG (identity: $IDENTITY)"
