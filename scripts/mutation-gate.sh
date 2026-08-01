#!/usr/bin/env bash
# Tier 6 of the verification harness: prove the test suite has teeth.
#
# A green suite only means something if it goes red when the code breaks. This
# applies a fixed set of mutations to real code one at a time and asserts
# `swift test` FAILS for each. A mutation that survives is a coverage gap — the
# suite would not have noticed that bug.
#
# Mutations are weighted toward the things this codebase treats as load-bearing:
# shellQuote (the device-shell security boundary) and newline splitting (the CRLF
# trap, where "\r\n" is one Swift Character).
#
# Slow by design — a full suite run per mutation. Intended for nightly or
# pre-release, not the edit loop. Usage: mutation-gate.sh [--list]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$ROOT/ADBKit"

die() {
  echo "error: $*" >&2
  exit 1
}

# file :: literal text to replace :: replacement :: what bug this simulates
MUTATIONS=(
  "Sources/ADBKit/Exec/AdbClient.swift
\"'\" + value.replacingOccurrences(of: \"'\", with: \"'\\\\''\") + \"'\"
value
shellQuote stops quoting entirely (command injection via any user value)"

  "Sources/ADBKit/Exec/AdbClient.swift
\"'\" + value.replacingOccurrences(of: \"'\", with: \"'\\\\''\") + \"'\"
\"'\" + value + \"'\"
shellQuote wraps but stops escaping embedded single quotes (quote-break escape)"

  "Sources/ADBKit/Devices/DeviceListParser.swift
output.split(omittingEmptySubsequences: true, whereSeparator: \\.isNewline)
output.split(omittingEmptySubsequences: true, whereSeparator: { \$0 == \"\\n\" })
device list splits on \\n only, so CRLF output parses as one line"

  "Sources/ADBKit/Features/PaneSplit.swift
min(fractionRange.upperBound, max(fractionRange.lowerBound, fraction))
fraction
pane split fraction stops being clamped to 30-70%"

  "Sources/ADBKit/Features/WindowEffects.swift
return min(max(opacity, minimumOpacity), 1.0)
return opacity
window opacity stops being clamped, so out-of-range values reach the renderer"
)

if [[ "${1:-}" == "--list" ]]; then
  i=0
  for m in "${MUTATIONS[@]}"; do
    i=$((i + 1))
    echo "$i. $(echo "$m" | sed -n '4p')"
    echo "   $(echo "$m" | sed -n '1p')"
  done
  exit 0
fi

# Mutations revert with `git checkout --`, which would discard uncommitted work in
# a target file. Check only those files: ADBKit/Package.resolved is rewritten by
# every `swift test` (SwiftPM and Xcode resolve different graphs into it), so a
# whole-directory check would refuse to run after any prior test invocation.
for m in "${MUTATIONS[@]}"; do
  target="$(echo "$m" | sed -n '1p')"
  git -C "$ROOT" diff --quiet -- "ADBKit/$target" ||
    die "uncommitted changes in $target — commit or stash first, mutations revert by checkout"
done

TOUCHED=()

restore() {
  for f in "${TOUCHED[@]:-}"; do
    [[ -n "$f" ]] && git -C "$ROOT" checkout -- "ADBKit/$f" 2>/dev/null || true
  done
}
trap restore EXIT

killed=0
survived=0
declare -a SURVIVORS=()

echo "── tier 6: mutation gate (${#MUTATIONS[@]} mutations) ──────────"

for m in "${MUTATIONS[@]}"; do
  file="$(echo "$m" | sed -n '1p')"
  old="$(echo "$m" | sed -n '2p')"
  new="$(echo "$m" | sed -n '3p')"
  desc="$(echo "$m" | sed -n '4p')"

  [[ -f "$KIT/$file" ]] || die "mutation target missing: $file"

  TOUCHED+=("$file")
  # Literal (quotemeta) replacement so Swift's quotes and backslashes survive.
  OLD="$old" NEW="$new" perl -0777 -i -pe 's/\Q$ENV{OLD}\E/$ENV{NEW}/' "$KIT/$file"

  # A mutation that failed to apply would look "killed" for the wrong reason.
  if git -C "$ROOT" diff --quiet -- "ADBKit/$file"; then
    die "mutation did not apply (text not found) in $file: $old"
  fi

  printf '  %-72s ' "$desc"
  if (cd "$KIT" && swift test >/dev/null 2>&1); then
    echo "SURVIVED"
    survived=$((survived + 1))
    SURVIVORS+=("$desc  [$file]")
  else
    echo "killed"
    killed=$((killed + 1))
  fi

  git -C "$ROOT" checkout -- "ADBKit/$file"
done

echo "───────────────────────────────────────────────────────────"
echo "killed: $killed   survived: $survived"

if ((survived > 0)); then
  echo
  echo "Survivors are coverage gaps — the suite would not catch these bugs:" >&2
  for s in "${SURVIVORS[@]}"; do echo "  - $s" >&2; done
  exit 1
fi
echo "mutation gate: OK — every mutation was caught"
