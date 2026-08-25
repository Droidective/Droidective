#!/usr/bin/env bash
# Builds droidectived and installs it where Tauri expects a sidecar.
#
# Tauri resolves an `externalBin` entry by appending the *target* triple, so
# the binary has to be named for the host it was built on. Getting that name
# wrong fails the Tauri build with "binary not found", which reads like a
# missing file rather than a misnamed one — hence deriving it from rustc
# rather than writing it down.
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="$ROOT/desktop/src-tauri/binaries"

case "$CONFIGURATION" in
debug | release) ;;
*)
  echo "usage: $(basename "$0") [debug|release]" >&2
  exit 2
  ;;
esac

command -v rustc >/dev/null || {
  echo "rustc is not on PATH — install Rust to build the desktop app" >&2
  exit 1
}
TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
[ -n "$TRIPLE" ] || {
  echo "could not read the host triple from rustc -vV" >&2
  exit 1
}

SUFFIX=""
case "$TRIPLE" in
*windows*) SUFFIX=".exe" ;;
esac

echo "building droidectived ($CONFIGURATION) for $TRIPLE"
(cd "$ROOT/droidectived" && swift build -c "$CONFIGURATION" --product droidectived)

BUILT="$ROOT/droidectived/.build/$CONFIGURATION/droidectived$SUFFIX"
[ -f "$BUILT" ] || {
  echo "expected a daemon at $BUILT, but swift build did not leave one there" >&2
  exit 1
}

mkdir -p "$DESTINATION"
# cp then chmod, not `install`: this script runs on the Windows runner too
# (Git Bash), where the coreutils set is trimmed and a missing `install` would
# fail the release with "command not found" rather than anything about the
# sidecar. chmod is a no-op on Windows and load-bearing everywhere else.
cp "$BUILT" "$DESTINATION/droidectived-$TRIPLE$SUFFIX"
chmod 755 "$DESTINATION/droidectived-$TRIPLE$SUFFIX"
echo "installed $DESTINATION/droidectived-$TRIPLE$SUFFIX"
