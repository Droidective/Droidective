#!/usr/bin/env bash
# Refresh the third-party binaries bundled in the app (App/Resources/), so the
# app stays self-contained (no `brew install scrcpy`/`ffmpeg`).
#
#   scripts/update-bundled-tools.sh [scrcpy_version]
#
# Downloads:
#   - scrcpy-server  from the scrcpy GitHub release (default v4.1)
#   - ffmpeg         latest static builds, macOS arm64 + x86_64
#                    (ffmpeg.martin-riedl.de), merged into one universal
#                    binary — the app ships universal, so every bundled
#                    Mach-O must carry both slices (CI enforces this).
#
# After running, bump the version constants in
# App/Sources/Bundled/BundledTools.swift if they changed (the scrcpy version
# MUST match the server payload), then `make build` and commit. The bundled
# ffmpeg is GPLv3 — see THIRD_PARTY_NOTICES.md.
set -euo pipefail

SCRCPY_VERSION="${1:-4.1}"
BUNDLETOOL_VERSION="${2:-1.18.3}"
UBER_APK_SIGNER_VERSION="${3:-1.3.0}"
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
FFMPEG_ARM64_SHA256="eaf91238e104dd0e262bc6510e25061855cc99a6955a721b0ac99660d58c473d"
FFMPEG_X86_64_SHA256="1ca59dda73668c59898a0b305afd8a88817a989187f222ec62d64e775d614d23"
BUNDLETOOL_SHA256="a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
UBER_APK_SIGNER_SHA256="e1299fd6fcf4da527dd53735b56127e8ea922a321128123b9c32d619bba1d835"

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

echo "==> ffmpeg (static, macOS arm64 + x86_64 → universal)"
mkdir -p "$TMP/ffmpeg-arm64" "$TMP/ffmpeg-x86_64"
curl -fsSL -o "$TMP/ffmpeg-arm64.zip" \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"
curl -fsSL -o "$TMP/ffmpeg-x86_64.zip" \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/release/ffmpeg.zip"
unzip -o -q "$TMP/ffmpeg-arm64.zip" -d "$TMP/ffmpeg-arm64"
unzip -o -q "$TMP/ffmpeg-x86_64.zip" -d "$TMP/ffmpeg-x86_64"
verify_sha256 "$TMP/ffmpeg-arm64/ffmpeg" "$FFMPEG_ARM64_SHA256" "ffmpeg (arm64)"
verify_sha256 "$TMP/ffmpeg-x86_64/ffmpeg" "$FFMPEG_X86_64_SHA256" "ffmpeg (x86_64)"

# Both slices must be the same ffmpeg version — a mixed-version universal
# binary would behave differently per Mac.
arm64_version="$("$TMP/ffmpeg-arm64/ffmpeg" -version | head -1 | cut -d' ' -f3)"
x86_64_version="$(arch -x86_64 "$TMP/ffmpeg-x86_64/ffmpeg" -version | head -1 | cut -d' ' -f3)"
if [[ "$arm64_version" != "$x86_64_version" ]]; then
  echo "ERROR: ffmpeg slice versions differ (arm64=$arm64_version, x86_64=$x86_64_version)" >&2
  echo "  The mirror is mid-publish — retry in a bit." >&2
  exit 1
fi

# Committed as per-arch slices (each under GitHub's 100 MB file limit); the
# fat binary is gitignored and assembled before every build.
mv "$TMP/ffmpeg-arm64/ffmpeg" "$RES/ffmpeg-arm64"
mv "$TMP/ffmpeg-x86_64/ffmpeg" "$RES/ffmpeg-x86_64"
"$ROOT/scripts/assemble-ffmpeg.sh"

ffmpeg_version="$arm64_version"

echo "==> bundletool $BUNDLETOOL_VERSION"
curl -fsSL -o "$TMP/bundletool-all.jar" \
  "https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/bundletool-all-${BUNDLETOOL_VERSION}.jar"
verify_sha256 "$TMP/bundletool-all.jar" "$BUNDLETOOL_SHA256" "bundletool"
mv "$TMP/bundletool-all.jar" "$RES/bundletool-all.jar"

echo "==> uber-apk-signer $UBER_APK_SIGNER_VERSION"
curl -fsSL -o "$TMP/uber-apk-signer.jar" \
  "https://github.com/patrickfav/uber-apk-signer/releases/download/v${UBER_APK_SIGNER_VERSION}/uber-apk-signer-${UBER_APK_SIGNER_VERSION}.jar"
verify_sha256 "$TMP/uber-apk-signer.jar" "$UBER_APK_SIGNER_SHA256" "uber-apk-signer"
mv "$TMP/uber-apk-signer.jar" "$RES/uber-apk-signer.jar"

echo
echo "Bundled (sha256):"
printf '  scrcpy-server    %s\n' "$(shasum -a 256 "$RES/scrcpy-server" | cut -d' ' -f1)"
printf '  ffmpeg           %s\n' "$(shasum -a 256 "$RES/ffmpeg" | cut -d' ' -f1)"
printf '  bundletool       %s\n' "$(shasum -a 256 "$RES/bundletool-all.jar" | cut -d' ' -f1)"
printf '  uber-apk-signer  %s\n' "$(shasum -a 256 "$RES/uber-apk-signer.jar" | cut -d' ' -f1)"
echo
echo "Versions: scrcpy=$SCRCPY_VERSION  ffmpeg=$ffmpeg_version  bundletool=$BUNDLETOOL_VERSION  uber-apk-signer=$UBER_APK_SIGNER_VERSION"
echo "Next: set BundledTools.scrcpyVersion / .bundletoolVersion / .uberApkSignerVersion"
echo "(and the matching pins in ManagedToolSpec.catalog) if they changed, update"
echo "THIRD_PARTY_NOTICES.md, then 'make build' and commit."
