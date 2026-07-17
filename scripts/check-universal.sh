#!/usr/bin/env bash
# Fail unless every Mach-O inside the app bundle carries both arm64 and
# x86_64. Guards the Intel-support promise (issue #174): a future bundled
# binary or build-setting change that ships single-arch would otherwise fail
# silently — Intel users just couldn't launch the app.
#
#   scripts/check-universal.sh <path-to.app>
#
# Zip archives (the bundled jars, scrcpy-server) pass through untouched —
# their embedded natives are the upstream jars' concern, not the bundle's.
set -euo pipefail

APP="${1:?usage: check-universal.sh <path-to.app>}"
failed=0
checked=0

while IFS= read -r -d '' f; do
  file -b "$f" | grep -q "Mach-O" || continue
  checked=$((checked + 1))
  archs="$(lipo -archs "$f" 2>/dev/null || true)"
  case "$archs" in
  *arm64*x86_64* | *x86_64*arm64*) ;;
  *)
    echo "NOT UNIVERSAL: $f (archs: ${archs:-unreadable})" >&2
    failed=1
    ;;
  esac
done < <(find "$APP" -type f -print0)

if [[ "$checked" -eq 0 ]]; then
  echo "ERROR: no Mach-O files found in $APP — wrong path?" >&2
  exit 1
fi
if [[ "$failed" -ne 0 ]]; then
  echo "ERROR: single-architecture Mach-O(s) in $APP — Intel Macs can't run this build." >&2
  exit 1
fi
echo "OK: all $checked Mach-O files in $APP are universal (arm64 + x86_64)."
