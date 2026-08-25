#!/usr/bin/env bash
# Builds the Linux desktop app in a container, from a macOS or Linux host.
#
# Tauri does not cross-compile — a Linux bundle has to be built on Linux — so
# without this the only place a Linux app could be produced was CI, and a CI
# job nobody can run locally is a job that is debugged one push at a time. The
# same recipe is what the release workflow runs, so a failure here is a failure
# there.
#
# The container is `swift:6.2-noble` because the daemon is the awkward
# dependency: it needs a Swift toolchain, and the Tauri side only needs Rust
# and Node, which are easy to add. One image builds both halves.
#
# Usage: build-desktop-linux.sh [debug|release]
set -euo pipefail

CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in
debug | release) ;;
*)
  echo "usage: $(basename "$0") [debug|release]" >&2
  exit 2
  ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/desktop/dist-linux"
# Survives the container, so a rerun is minutes rather than most of an hour.
CACHE="$ROOT/desktop/.linux-cache"

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

# Deliberately no apt cache: apt fetches as the unprivileged `_apt` user,
# which cannot write into a host-mounted archives directory, and the failure
# is a "Permission denied" on every download rather than a mount error. The
# cargo registry and target dir are where the time actually goes anyway.
mkdir -p "$OUT" "$CACHE/cargo" "$CACHE/target"

# The repo is mounted read-only and copied to a scratch tree inside the
# container. Building in the mount would put Linux `node_modules` and a Linux
# `target/` on top of the host's macOS ones, which then have to be thrown away
# before anything can be built on the host again.
#
# `dist-linux` is mounted writable so the bundles survive the container.
# The configuration rides in as an environment variable rather than being
# interpolated into the script text: a value spliced into a quoted heredoc is a
# quoting bug waiting to happen, and shellcheck cannot see through it either.
# Swift's BoringSSL and NIO builds stall in the 1 GB a container gets by
# default — the same reason `make test-linux` asks for headroom. Rust's
# codegen wants it too.
exec "$RUNTIME" run --rm \
  --cpus "${BUILD_CPUS:-8}" --memory 10g \
  --env "CONFIGURATION=$CONFIGURATION" \
  --env CARGO_TARGET_DIR=/cache/target \
  --volume "$ROOT:/repo:ro" \
  --volume "$OUT:/out" \
  --volume "$CACHE/cargo:/root/.cargo-registry" \
  --volume "$CACHE/target:/cache/target" \
  swift:6.2-noble \
  bash -euo pipefail -c "
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Tauri's Linux prerequisites. webkit2gtk 4.1 is the one that matters: 4.0 is
# the GTK3/soup2 build Tauri 1 used, and linking against it fails late and
# confusingly.
apt-get install -y -qq --no-install-recommends \
  build-essential curl wget file rsync ca-certificates pkg-config \
  libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev \
  librsvg2-dev libssl-dev libxdo-dev patchelf desktop-file-utils \
  xdg-utils fakeroot

curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
. \"\$HOME/.cargo/env\"
# Crate sources are the other slow download; keep them beside the target dir.
mkdir -p /root/.cargo-registry/registry /root/.cargo-registry/git
ln -sfn /root/.cargo-registry/registry /root/.cargo/registry
ln -sfn /root/.cargo-registry/git /root/.cargo/git

curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y -qq nodejs

# Copy out of the read-only mount, leaving behind everything host-built.
mkdir -p /work
rsync -a --exclude node_modules --exclude .build --exclude target \
  --exclude DerivedData --exclude .git /repo/ /work/
cd /work

# The shared recipe: it sets the version from PORT_VERSION, picks the bundlers,
# and leaves canonically-named bundles straight in /out. No copy step here —
# package-desktop.sh is what names them, on this path and in CI alike.
./scripts/build-desktop-app.sh linux \"\$CONFIGURATION\" /out
ls -la /out
"
