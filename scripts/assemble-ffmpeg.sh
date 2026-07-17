#!/usr/bin/env bash
# Stage the bundled ffmpeg from the committed per-arch slices (each under
# GitHub's 100 MB file limit; the fat binary isn't, so it's gitignored).
#
#   scripts/assemble-ffmpeg.sh [universal|arm64|x86_64]
#
# universal (default) lipos both slices — local dev builds, so one Debug app
# runs anywhere. Release builds are thin per arch and pass their arch so the
# DMG only carries the slice it can execute.
set -euo pipefail

MODE="${1:-universal}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/App/Resources"
OUT="$RES/ffmpeg"

case "$MODE" in
universal)
  if [[ -f "$OUT" && "$OUT" -nt "$RES/ffmpeg-arm64" && "$OUT" -nt "$RES/ffmpeg-x86_64" ]] &&
    [[ "$(lipo -archs "$OUT" 2>/dev/null)" == *arm64*x86_64* || "$(lipo -archs "$OUT" 2>/dev/null)" == *x86_64*arm64* ]]; then
    exit 0
  fi
  lipo -create "$RES/ffmpeg-arm64" "$RES/ffmpeg-x86_64" -output "$OUT"
  ;;
arm64 | x86_64)
  cp -f "$RES/ffmpeg-$MODE" "$OUT"
  ;;
*)
  echo "usage: assemble-ffmpeg.sh [universal|arm64|x86_64]" >&2
  exit 1
  ;;
esac
chmod +x "$OUT"
echo "Staged ffmpeg ($MODE): $(lipo -archs "$OUT")"
