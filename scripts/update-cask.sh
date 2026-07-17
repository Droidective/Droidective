#!/usr/bin/env bash
# Render the Homebrew cask for a release. The release job runs this against a
# checkout of the tap repo, then commits the result. Releases ship one DMG
# per architecture, so the cask selects by CPU (arm/intel blocks).
#
# Usage: update-cask.sh <version> <arm64-dmg> <arm64-url> <x86_64-dmg> <x86_64-url> <cask-file>
set -euo pipefail

VERSION="${1:?version required}"
DMG_ARM="${2:?arm64 dmg path required}"
URL_ARM="${3:?arm64 download url required}"
DMG_X86="${4:?x86_64 dmg path required}"
URL_X86="${5:?x86_64 download url required}"
OUT="${6:?output cask path required}"

for dmg in "$DMG_ARM" "$DMG_X86"; do
  [[ -f "$dmg" ]] || {
    echo "error: DMG not found: $dmg" >&2
    exit 1
  }
done

SHA_ARM="$(shasum -a 256 "$DMG_ARM" | awk '{print $1}')"
SHA_X86="$(shasum -a 256 "$DMG_X86" | awk '{print $1}')"
mkdir -p "$(dirname "$OUT")"

cat >"$OUT" <<RUBY
cask "droidective" do
  arch arm: "arm64", intel: "x86_64"

  version "${VERSION}"
  sha256 arm:   "${SHA_ARM}",
         intel: "${SHA_X86}"

  on_arm do
    url "${URL_ARM}"
  end
  on_intel do
    url "${URL_X86}"
  end

  name "Droidective"
  desc "Native macOS app for Android and React Native debugging over adb"
  homepage "https://droidective.com/"

  # Sparkle updates the app in place, so Homebrew should not fight it.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Droidective.app"

  zap trash: [
    "~/Library/Application Support/Droidective",
    "~/Library/Preferences/com.rohindh.droidective.plist",
  ]
end
RUBY

echo "wrote $OUT (v${VERSION}, arm64 ${SHA_ARM}, x86_64 ${SHA_X86})"
