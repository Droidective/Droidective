#!/usr/bin/env bash
# Unpack the bundled ffmpeg from its committed archive. The universal binary
# (arm64 + x86_64, ~152 MB) exceeds GitHub's 100 MB file limit, so the repo
# carries App/Resources/ffmpeg.zip and the unpacked binary is gitignored.
# Run before `xcodegen generate` (the Makefile and CI both do) — the project
# references App/Resources/ffmpeg as a bundled resource. No-op when the
# unpacked binary is already up to date.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/App/Resources"

if [[ ! -f "$RES/ffmpeg.zip" ]]; then
  echo "error: $RES/ffmpeg.zip not found — run scripts/update-bundled-tools.sh" >&2
  exit 1
fi

if [[ ! -f "$RES/ffmpeg" || "$RES/ffmpeg.zip" -nt "$RES/ffmpeg" ]]; then
  unzip -o -q "$RES/ffmpeg.zip" -d "$RES"
  chmod +x "$RES/ffmpeg"
  # unzip restores the archived mtime, which predates the zip — bump it so the
  # staleness check above short-circuits on the next run.
  touch "$RES/ffmpeg"
  echo "unpacked App/Resources/ffmpeg"
fi

archs="$(lipo -archs "$RES/ffmpeg")"
if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
  echo "error: unpacked ffmpeg is not universal (archs: $archs)" >&2
  exit 1
fi
