#!/usr/bin/env bash
# Package a built droidectived binary into the archive its channel publishes.
#
# A script rather than inline YAML so the naming — which
# release-channel.sh asserts against — lives next to the policy it has to match,
# and so a packaging change can be run locally instead of only on a tag.
#
# Usage: package-daemon.sh <version> <platform> <binary> <out-dir>
#   version   3.9.0-beta.1   (no leading v)
#   platform  macos-universal | linux-x86_64 | windows-x86_64
#   binary    path to the built droidectived
#   out-dir   where the archive lands
set -euo pipefail

VERSION="${1:?version}"
PLATFORM="${2:?platform}"
BINARY="${3:?binary}"
OUT_DIR="${4:?out dir}"

[[ -f "$BINARY" ]] || {
  echo "error: no daemon binary at $BINARY" >&2
  exit 1
}

case "$PLATFORM" in
macos-universal | linux-x86_64 | windows-x86_64) ;;
*)
  echo "error: unknown platform '$PLATFORM'" >&2
  exit 1
  ;;
esac

mkdir -p "$OUT_DIR"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# The archive holds the binary and its licence, nothing else. A sidecar the UI
# spawns has no use for a directory tree, and a flat archive is one less thing
# for the installer to get wrong.
if [[ "$PLATFORM" == windows-x86_64 ]]; then
  cp "$BINARY" "$STAGE/droidectived.exe"
else
  cp "$BINARY" "$STAGE/droidectived"
  chmod 755 "$STAGE/droidectived"
fi
cp LICENSE "$STAGE/LICENSE" 2>/dev/null || true

ARCHIVE="droidectived-${VERSION}-${PLATFORM}"
if [[ "$PLATFORM" == windows-x86_64 ]]; then
  (cd "$STAGE" && zip -q -r "${ARCHIVE}.zip" .)
  mv "$STAGE/${ARCHIVE}.zip" "$OUT_DIR/"
  echo "packaged $OUT_DIR/${ARCHIVE}.zip"
else
  # Entries named explicitly and in a fixed order, so rebuilding the same commit
  # lays the archive out the same way and a changed checksum points at changed
  # code rather than at tar's directory-walk order. (Not `mapfile`: macOS ships
  # bash 3.2, where it does not exist.)
  entries=(droidectived)
  [[ -f "$STAGE/LICENSE" ]] && entries+=(LICENSE)
  (cd "$STAGE" && tar --format=ustar -czf "${ARCHIVE}.tar.gz" "${entries[@]}")
  mv "$STAGE/${ARCHIVE}.tar.gz" "$OUT_DIR/"
  echo "packaged $OUT_DIR/${ARCHIVE}.tar.gz"
fi
