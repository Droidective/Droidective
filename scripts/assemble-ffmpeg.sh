#!/usr/bin/env bash
# Assemble the universal ffmpeg bundled into the app from the two committed
# per-arch slices. The slices are committed (each under GitHub's 100 MB file
# limit) and the fat binary is gitignored (152 MB — over it), so every build
# path runs this first: Makefile `generate` and the CI build/release jobs.
# Idempotent — skips when the output is newer than both slices.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/App/Resources"
OUT="$RES/ffmpeg"

if [[ -f "$OUT" && "$OUT" -nt "$RES/ffmpeg-arm64" && "$OUT" -nt "$RES/ffmpeg-x86_64" ]]; then
  exit 0
fi
lipo -create "$RES/ffmpeg-arm64" "$RES/ffmpeg-x86_64" -output "$OUT"
chmod +x "$OUT"
echo "Assembled universal ffmpeg: $(lipo -archs "$OUT")"
