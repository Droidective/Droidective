#!/usr/bin/env bash
# Tier 4a of the verification harness: does the built mac app actually come up?
#
# Deliberately thin. `make build` proves it compiles and the AppTests bundle
# proves the pure logic works, but neither catches a crash on launch, a missing
# bundled resource, or a window that never appears — the failures that make the
# app useless while every other gate stays green.
#
# Kept minimal on purpose: SwiftUI is the hard surface to automate and it is the
# layer the cross-platform work eventually replaces, so this checks liveness and
# leaves interaction testing to the web UI's Playwright suite.
#
# Usage: mac-smoke.sh [--keep] [--shot PATH]
#   --keep       leave the app running afterwards
#   --shot PATH  write the window screenshot here (default: a temp file)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/DerivedData/Build/Products/Debug/Droidective.app"
BIN="$APP/Contents/MacOS/Droidective"
SETTLE_SECONDS=6
# A window can take longer than the liveness settle on a cold start.
WINDOW_TIMEOUT=45

KEEP=0
SHOT=""

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --keep)
    KEEP=1
    shift
    ;;
  --shot)
    SHOT="${2:?--shot needs a path}"
    shift 2
    ;;
  *) die "unknown argument '$1'" ;;
  esac
done

[[ -x "$BIN" ]] || die "no Debug build at $APP — run 'make build' first"
[[ -n "$SHOT" ]] || SHOT="$(mktemp -t droidective-smoke).png"

cleanup() {
  if ((KEEP == 0)); then
    pkill -x Droidective 2>/dev/null || true
  fi
}
trap cleanup EXIT

# `open` activates an already-running instance instead of launching the new
# build, so a stale process would make this test pass against old code.
pkill -x Droidective 2>/dev/null || true
sleep 0.5
pgrep -x Droidective >/dev/null && die "a Droidective instance survived pkill"

# A release build installed over the Debug bundle (Sparkle staging an update on
# quit) shows up as a binary far older than the build — check before trusting it.
if [[ ! -f "$APP/Contents/MacOS/Droidective.debug.dylib" ]]; then
  die "no Droidective.debug.dylib in the bundle — this looks like a Release build in the Debug path"
fi

echo "── launching $(basename "$APP")"
open "$APP"

# Poll rather than sleep-then-check, so a crash is reported as a crash instead of
# as an absent window.
deadline=$((SECONDS + SETTLE_SECONDS))
while ((SECONDS < deadline)); do
  pgrep -x Droidective >/dev/null || die "the app exited during launch (crash on startup)"
  sleep 1
done

pid="$(pgrep -x Droidective | head -1)"
echo "── still running after ${SETTLE_SECONDS}s (pid $pid)"

# Compare launch time against the binary's mtime: if the running process predates
# the build, `open` re-activated something stale and the run proves nothing.
bin_epoch="$(stat -f %m "$BIN")"
proc_started="$(ps -o lstart= -p "$pid" | head -1)"
proc_epoch="$(date -j -f "%a %b %d %T %Y" "$proc_started" +%s 2>/dev/null || echo 0)"
if ((proc_epoch > 0 && proc_epoch < bin_epoch)); then
  die "running process started before the binary was built — a stale instance is in front"
fi

# A locked or sleeping display reports zero windows to System Events and makes
# `screencapture` return an all-black frame, so the window checks below would
# fail for reasons that have nothing to do with the app. Liveness above is the
# part that matters and it holds regardless, so report and stop rather than
# claiming a failure — an unattended run on a locked Mac must not look like a
# regression.
if [[ "$(ioreg -n Root -d1 -a 2>/dev/null | plutil -extract IOConsoleLocked raw -o - - 2>/dev/null)" == "true" ]]; then
  echo "── display is locked: skipping the window and screenshot checks"
  echo "───────────────────────────────────────────────────────────"
  echo "mac smoke: OK (liveness only — unlock the display for the full check)"
  exit 0
fi

# A window, via the accessibility tree rather than pixel guessing. Polled, not
# checked once: a cold start right after a rebuild can outlast any fixed settle,
# and a fixed sleep either makes the test flaky or makes every run pay the
# worst case.
windows=0
window_deadline=$((SECONDS + WINDOW_TIMEOUT))
while ((SECONDS < window_deadline)); do
  windows="$(osascript -e 'tell application "System Events" to tell process "Droidective" to count windows' 2>/dev/null || echo 0)"
  [[ "$windows" -ge 1 ]] && break
  pgrep -x Droidective >/dev/null || die "the app exited while waiting for its window"
  sleep 1
done
[[ "$windows" -ge 1 ]] ||
  die "no window in the accessibility tree after ${WINDOW_TIMEOUT}s (count=$windows)"
echo "── window count: $windows"

title="$(osascript -e 'tell application "System Events" to tell process "Droidective" to get title of window 1' 2>/dev/null || echo "")"
echo "── front window title: ${title:-(none)}"

screencapture -x -o "$SHOT" 2>/dev/null || die "screencapture failed"
[[ -s "$SHOT" ]] || die "screenshot is empty"
echo "── screenshot: $SHOT ($(stat -f %z "$SHOT") bytes)"

echo "───────────────────────────────────────────────────────────"
echo "mac smoke: OK"
