#!/usr/bin/env bash
# Refresh the third-party binaries bundled in the app (App/Resources/), so the
# app stays self-contained (no `brew install scrcpy`/`ffmpeg`).
#
#   scripts/update-bundled-tools.sh [scrcpy_version]
#
# Downloads:
#   - scrcpy-server  from the scrcpy GitHub release (default v4.1)
#   - ffmpeg         latest static build, macOS arm64 (ffmpeg.martin-riedl.de)
#
# After running, bump the version constants in
# App/Sources/Bundled/BundledTools.swift if they changed (the scrcpy version
# MUST match the server payload), then `make build` and commit. The bundled
# ffmpeg is GPLv3 — see THIRD_PARTY_NOTICES.md.
set -euo pipefail

SCRCPY_VERSION="${1:-4.1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/App/Resources"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Expected SHA-256 of each download. These pin the exact bytes shipped inside a
# notarized, GPLv3-bundling app: a download whose hash doesn't match is rejected
# rather than silently bundled. When intentionally updating a binary, run the
# script, read the "got" hash from the mismatch error, and update the constant
# here in the same commit that bumps the version.
SCRCPY_SERVER_SHA256="deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae"
FFMPEG_SHA256="eaf91238e104dd0e262bc6510e25061855cc99a6955a721b0ac99660d58c473d"

verify_sha256() {
  local file="$1" expected="$2" name="$3"
  local got
  got="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  if [[ "$got" != "$expected" ]]; then
    echo "ERROR: $name sha256 mismatch" >&2
    echo "  expected $expected" >&2
    echo "  got      $got" >&2
    echo "  If this update is intentional, set the constant in this script to the got value." >&2
    exit 1
  fi
}

echo "==> scrcpy-server v$SCRCPY_VERSION"
curl -fsSL -o "$TMP/scrcpy-server" \
  "https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/scrcpy-server-v${SCRCPY_VERSION}"
verify_sha256 "$TMP/scrcpy-server" "$SCRCPY_SERVER_SHA256" "scrcpy-server"
mv "$TMP/scrcpy-server" "$RES/scrcpy-server"

echo "==> ffmpeg (static, macOS arm64)"
curl -fsSL -o "$TMP/ffmpeg.zip" \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"
unzip -o -q "$TMP/ffmpeg.zip" -d "$TMP"
verify_sha256 "$TMP/ffmpeg" "$FFMPEG_SHA256" "ffmpeg"
mv "$TMP/ffmpeg" "$RES/ffmpeg"
chmod +x "$RES/ffmpeg"

ffmpeg_version="$("$RES/ffmpeg" -version | head -1 | cut -d' ' -f3)"

echo
echo "Bundled (sha256):"
printf '  scrcpy-server  %s\n' "$(shasum -a 256 "$RES/scrcpy-server" | cut -d' ' -f1)"
printf '  ffmpeg         %s\n' "$(shasum -a 256 "$RES/ffmpeg" | cut -d' ' -f1)"
echo
echo "Versions: scrcpy=$SCRCPY_VERSION  ffmpeg=$ffmpeg_version"
echo "Next: set BundledTools.scrcpyVersion=\"$SCRCPY_VERSION\" if it changed,"
echo "update the ffmpeg version in THIRD_PARTY_NOTICES.md, then 'make build' and commit."
