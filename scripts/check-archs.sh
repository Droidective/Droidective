#!/usr/bin/env bash
# Fail unless every Mach-O inside the app bundle carries ALL the required
# architectures. Guards the per-arch release promise (issue #174): a bundled
# binary or build setting shipping the wrong slice would otherwise fail
# silently — users on that CPU just couldn't launch the app.
#
#   scripts/check-archs.sh <path-to.app> <arch> [arch...]
#
# Release builds pass their single target arch; pass both for a universal
# build. Zip archives (the bundled jars, scrcpy-server) pass through — their
# embedded natives are the upstream jars' concern, not the bundle's.
set -euo pipefail

APP="${1:?usage: check-archs.sh <path-to.app> <arch> [arch...]}"
shift
[[ $# -ge 1 ]] || {
  echo "usage: check-archs.sh <path-to.app> <arch> [arch...]" >&2
  exit 1
}
required=("$@")
failed=0
checked=0

while IFS= read -r -d '' f; do
  file -b "$f" | grep -q "Mach-O" || continue
  checked=$((checked + 1))
  archs="$(lipo -archs "$f" 2>/dev/null || true)"
  for want in "${required[@]}"; do
    case " $archs " in
    *" $want "*) ;;
    *)
      echo "MISSING $want: $f (archs: ${archs:-unreadable})" >&2
      failed=1
      ;;
    esac
  done
done < <(find "$APP" -type f -print0)

if [[ "$checked" -eq 0 ]]; then
  echo "ERROR: no Mach-O files found in $APP — wrong path?" >&2
  exit 1
fi
if [[ "$failed" -ne 0 ]]; then
  echo "ERROR: Mach-O(s) in $APP are missing required slices (${required[*]}) — Macs on that CPU can't run this build." >&2
  exit 1
fi
echo "OK: all $checked Mach-O files in $APP carry: ${required[*]}."
