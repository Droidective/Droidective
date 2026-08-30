#!/usr/bin/env bash
# Installs the built .deb in a clean container and proves the app comes up.
#
# The point is what a build alone cannot tell you: that the package's declared
# dependencies are actually enough. The build container has every -dev package
# Tauri needed to compile; a user's machine has none of them, so this starts
# from bare `ubuntu:24.04` and lets `apt install ./the.deb` pull whatever the
# control file says it needs. A missing runtime depend fails here rather than
# on someone's laptop.
#
# It found one the first time it was run: the daemon was dynamically linked
# against the Swift runtime, so `droidectived` died at exec with
# "libswiftCore.so: cannot open shared object file" and every screen sat behind
# "droidectived would not start". The build machine had a toolchain; nobody
# else does. That is the class of bug this exists for, which is why each check
# below is an `exit 1` and not a warning — the first version of this script
# printed "WARNING: no droidectived process" and exited 0.
#
# There is no display in a container, so the app runs under Xvfb and the
# virtual framebuffer is photographed. Four things have to hold:
#
#   1. the process is still alive after the window should have appeared,
#   2. the daemon it spawns is alive too — without it the app is a banner,
#   3. a window exists at the size the config asks for, and
#   4. the framebuffer is not a flat rectangle, and changes when driven.
#
# "It did not immediately exit" on its own is not evidence of any of that.
#
# Usage: smoke-desktop-linux.sh [path-to-deb]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/desktop/dist-linux"

DEB="${1:-}"
if [ -z "$DEB" ]; then
  DEB="$(find "$DIST" -maxdepth 1 -name '*.deb' | head -1)"
fi
[ -n "$DEB" ] && [ -f "$DEB" ] || {
  echo "no .deb found — run scripts/build-desktop-linux.sh first" >&2
  exit 1
}
# The .deb may live anywhere the caller likes; only its directory is mounted.
DEB_DIR="$(cd "$(dirname "$DEB")" && pwd)"

RUNTIME="${RUNTIME:-}"
if [ -z "$RUNTIME" ]; then
  for candidate in container docker podman; do
    if command -v "$candidate" >/dev/null 2>&1; then
      RUNTIME="$candidate"
      break
    fi
  done
fi
[ -n "$RUNTIME" ] || {
  echo "no container runtime found (tried container, docker, podman)" >&2
  exit 1
}

echo "smoke-testing $(basename "$DEB") via $RUNTIME"

# The container script is single-quoted on purpose: nothing in it should be
# expanded by this shell. What it needs comes in through --env.
# shellcheck disable=SC2016
exec "$RUNTIME" run --rm \
  --cpus 4 --memory 4g \
  --env "DEB_NAME=$(basename "$DEB")" \
  --volume "$DEB_DIR:/dist" \
  ubuntu:24.04 \
  bash -euo pipefail -c '
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Nothing from the build image. apt resolves the Depends declared by the
# package itself, which is the half of it this test exists to check.
apt-get install -y -qq "/dist/$DEB_NAME"

# Only the harness is extra: a virtual display, something to photograph it,
# and something to type into it.
apt-get install -y -qq --no-install-recommends \
  xvfb x11-utils imagemagick procps xdotool iproute2 curl

Xvfb :99 -screen 0 1400x900x24 >/tmp/xvfb.log 2>&1 &
for _ in $(seq 30); do xdpyinfo -display :99 >/dev/null 2>&1 && break; sleep 1; done
xdpyinfo -display :99 >/dev/null || { echo "Xvfb never came up"; cat /tmp/xvfb.log; exit 1; }

export DISPLAY=:99
# WebKitGTK has no GPU here, and its sandbox needs kernel features a container
# does not grant. Neither is a property of the app.
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export LIBGL_ALWAYS_SOFTWARE=1

fail() { echo "SMOKE FAILED: $*"; echo "=== app log ==="; cat /tmp/app.log || true; exit 1; }

droidective-desktop >/tmp/app.log 2>&1 &
APP=$!
sleep 25

kill -0 "$APP" 2>/dev/null || fail "the app exited"
echo "=== still running after 25s (pid $APP) ==="

# The daemon is spawned by the app, so finding it proves the sidecar was
# bundled, was executable, was found at the name Tauri derives — and, the one
# this caught, that it can resolve its shared libraries on a machine with no
# Swift toolchain. Without it every screen is a banner, so this is fatal.
pgrep -a droidectived || fail "the app is up but droidectived is not running"

# It is listening, and it serves the registry. Asked over the wire rather than
# inferred from the process being alive: a daemon that starts and then answers
# nothing is a window full of empty screens, and this separates "the daemon is
# broken" from "the client cannot reach it" before anything is driven.
PORT="$(ss -ltnp 2>/dev/null | sed -nE "s/.*127\.0\.0\.1:([0-9]+).*droidectived.*/\1/p" | head -1)"
[ -n "$PORT" ] || fail "droidectived is running but is not listening on loopback"
TOKEN_FILE="$HOME/.local/share/com.rohindh.droidective.desktop/droidectived.token"
[ -f "$TOKEN_FILE" ] || fail "no token file at $TOKEN_FILE"
FEATURES="$(curl -s -X POST "http://127.0.0.1:$PORT/v1/features/list" \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")" | tr "," "\n" | grep -c "\"id\"" || true)"
echo "=== the daemon serves $FEATURES features on port $PORT ==="
[ "$FEATURES" -ge 50 ] || fail "the daemon served $FEATURES features, which is not a registry"

# The one call both ports fell over on. `adb devices` on a machine whose adb
# server is not running forks that server and exits, and the runner used to
# miss that exit and wait for it forever; the app came up with "0 features" and
# no error to explain it. There is no device here and there does not need to be
# — an *empty* answer is fine, an answer *arriving* is the assertion. Timed,
# because a slow answer and a hung one are the same screenshot.
DEVICES_START="$(date +%s)"
curl -s --max-time 30 -o /tmp/devices.json -X POST "http://127.0.0.1:$PORT/v1/devices/list" \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
  || fail "the first /v1/devices/list never came back — the hang the ports fell over on"
DEVICES_ELAPSED="$(($(date +%s) - DEVICES_START))"
echo "=== first /v1/devices/list answered in ${DEVICES_ELAPSED}s: $(head -c 120 /tmp/devices.json) ==="
[ "$DEVICES_ELAPSED" -le 10 ] \
  || fail "the first device list took ${DEVICES_ELAPSED}s, which is a launch nobody would wait out"

echo "=== window tree ==="
xwininfo -root -children -display :99 | tee /tmp/windows.txt
grep -q "\"Droidective\"" /tmp/windows.txt || fail "no window named Droidective"

WINDOW="$(xdotool search --name "^Droidective$" | head -1)"
[ -n "$WINDOW" ] || fail "xdotool cannot find the window"

import -window root -display :99 /dist/linux-launch.png

# A blank framebuffer is what a webview that never painted looks like, and it
# passes every check above. The standard deviation of a flat rectangle is 0;
# a drawn UI is far from it.
spread() { identify -format "%[fx:standard_deviation*255]" "$1"; }
LAUNCH_SPREAD="$(spread /dist/linux-launch.png)"
echo "launch pixel spread: $LAUNCH_SPREAD"
[ "${LAUNCH_SPREAD%%.*}" -ge 3 ] || fail "the window painted nothing (spread $LAUNCH_SPREAD)"

# Drive it far enough to open a screen. There is no window manager here, so
# focus is set directly rather than by clicking. Ctrl+K is the command
# palette; the Terminal is the screen to ask for, because it is the one that
# proves the whole stack — the daemon opens a real pty and xterm.js draws what
# the shell wrote.
#
# Escape at the end is what makes the check mean something. Without it the
# palette itself is a large overlay, so "pixels changed" is satisfied by the
# palette having *opened* whether or not the choice landed — which is exactly
# what happened when the client had no features to offer: the palette appeared,
# said "Nothing matches", and the frame diff called that a screen. With the
# palette dismissed, the picture differs only if a tab really opened.
xdotool windowfocus "$WINDOW" || true
xdotool key --window "$WINDOW" ctrl+k
sleep 2
xdotool type --window "$WINDOW" --delay 60 "terminal"
sleep 2
xdotool key --window "$WINDOW" Return
sleep 10
import -window root -display :99 /dist/linux-palette.png
xdotool key --window "$WINDOW" Escape
sleep 3

import -window root -display :99 /dist/linux-screen.png
SCREEN_SPREAD="$(spread /dist/linux-screen.png)"
echo "screen pixel spread: $SCREEN_SPREAD"

# Same picture means nothing opened. `compare -metric AE` counts differing
# pixels; a tab plus a terminal is tens of thousands of them, while a couple of
# hundred is a caret blinking.
CHANGED="$(compare -metric AE /dist/linux-launch.png /dist/linux-screen.png null: 2>&1 || true)"
echo "pixels changed after opening a screen: $CHANGED"
case "$CHANGED" in
  *[!0-9]*|"") fail "could not compare the two frames (got: $CHANGED)" ;;
esac
[ "$CHANGED" -gt 5000 ] || fail "the palette opened nothing ($CHANGED pixels changed)"

kill -0 "$APP" 2>/dev/null || fail "the app died while a screen was being opened"

echo "=== app log ==="
tail -20 /tmp/app.log || true
kill "$APP" 2>/dev/null || true
ls -la /dist/linux-launch.png /dist/linux-palette.png /dist/linux-screen.png
echo "SMOKE PASSED"
'
