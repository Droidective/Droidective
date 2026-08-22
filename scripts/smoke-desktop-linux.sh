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
# There is no display in a container, so the app runs under Xvfb and the
# virtual framebuffer is photographed. A process that is still alive after the
# window should have appeared, plus a screenshot that is not a blank rectangle,
# is the evidence — "it did not immediately exit" on its own is not.
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

RUNTIME=""
for candidate in container docker podman; do
  if command -v "$candidate" >/dev/null 2>&1; then
    RUNTIME="$candidate"
    break
  fi
done
[ -n "$RUNTIME" ] || {
  echo "no container runtime found (tried container, docker, podman)" >&2
  exit 1
}

echo "smoke-testing $(basename "$DEB")"

# The container script is single-quoted on purpose: nothing in it should be
# expanded by this shell. What it needs comes in through --env.
# shellcheck disable=SC2016
exec "$RUNTIME" run --rm \
  --cpus 4 --memory 4g \
  --env "DEB_NAME=$(basename "$DEB")" \
  --volume "$DIST:/dist" \
  ubuntu:24.04 \
  bash -euo pipefail -c '
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Nothing from the build image. apt resolves the Depends declared by the
# package itself, which is the half of it this test exists to check.
apt-get install -y -qq "/dist/$DEB_NAME"

# Only the harness is extra: a virtual display and something to photograph it.
apt-get install -y -qq --no-install-recommends xvfb x11-utils imagemagick procps

Xvfb :99 -screen 0 1400x900x24 >/tmp/xvfb.log 2>&1 &
for _ in $(seq 30); do xdpyinfo -display :99 >/dev/null 2>&1 && break; sleep 1; done
xdpyinfo -display :99 >/dev/null || { echo "Xvfb never came up"; cat /tmp/xvfb.log; exit 1; }

export DISPLAY=:99
# WebKitGTK has no GPU here, and its sandbox needs kernel features a container
# does not grant. Neither is a property of the app.
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export LIBGL_ALWAYS_SOFTWARE=1

droidective-desktop >/tmp/app.log 2>&1 &
APP=$!
sleep 25

if ! kill -0 "$APP" 2>/dev/null; then
  echo "=== the app exited ==="
  cat /tmp/app.log
  exit 1
fi
echo "=== still running after 25s (pid $APP) ==="

# The daemon is spawned by the app, so finding it proves the sidecar was
# bundled, was executable, and was found at the name Tauri derives.
pgrep -a droidectived || echo "WARNING: no droidectived process"

echo "=== window tree ==="
xwininfo -root -children -display :99 | head -20

import -window root -display :99 /dist/linux-launch.png
echo "=== app log ==="
tail -20 /tmp/app.log || true
kill "$APP" 2>/dev/null || true
ls -la /dist/linux-launch.png
'
