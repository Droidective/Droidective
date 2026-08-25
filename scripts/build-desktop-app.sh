#!/usr/bin/env bash
# Build the desktop app for the host platform and leave canonically-named
# bundles in an output directory.
#
# This is the recipe itself, with no opinion about where it runs. Two callers
# share it, which is the point:
#
#   * build-desktop-linux.sh runs it inside a swift:6.2-noble container, so a
#     Linux bundle can be produced from a macOS host.
#   * the release workflow's desktop-artifacts job runs it directly — on Linux
#     inside that same image, and on Windows on the runner.
#
# Before this existed the container recipe and the CI recipe were separate
# copies of the same steps, and only one of them was ever run locally. A build
# nobody can reproduce off CI is a build debugged one push at a time.
#
# Toolchains are the caller's job: installing Swift, Rust and Node differs per
# environment and does not belong in the recipe. What this owns is the part that
# must be identical everywhere — which version the bundles carry, which
# bundlers run, and what the outputs are called.
#
# Usage: build-desktop-app.sh <linux|windows> [debug|release] [out-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=release-channel.sh
source "$ROOT/scripts/release-channel.sh"

PLATFORM="${1:?platform required: linux or windows}"
CONFIGURATION="${2:-release}"
OUT_DIR="${3:-$ROOT/desktop/dist-app}"

# Absolute before anything changes directory. This script cds into desktop/ to
# run npm, so a *relative* out-dir would resolve there rather than against the
# caller's cwd — which is exactly what the first beta tag did: the bundles were
# built correctly and written to desktop/dist while the workflow looked for
# dist/ at the repo root, and the upload failed with "no files were found" on a
# build that had actually succeeded.
#
# The second pattern is for Git Bash on the Windows runner, where an absolute
# path is `C:/…` and would otherwise be treated as relative.
case "$OUT_DIR" in
/* | [A-Za-z]:[/\\]*) ;;
*) OUT_DIR="$(pwd)/$OUT_DIR" ;;
esac

case "$PLATFORM" in
# Deliberately not the config's "targets": "all". On Linux that adds an .rpm
# nothing publishes and rpmbuild is not installed; on Windows it would try
# every installer format. Naming the bundlers here keeps the release's artifact
# set and the build's outputs the same list.
linux) BUNDLES="deb,appimage" ;;
windows) BUNDLES="nsis,msi" ;;
*)
  echo "error: unknown platform '$PLATFORM' (expected linux or windows)" >&2
  exit 2
  ;;
esac

case "$CONFIGURATION" in
debug | release) ;;
*)
  echo "usage: $(basename "$0") <linux|windows> [debug|release] [out-dir]" >&2
  exit 2
  ;;
esac

for tool in rustc cargo node npm swift; do
  command -v "$tool" >/dev/null || {
    echo "error: $tool is not on PATH — the caller installs the toolchains" >&2
    exit 1
  }
done

PORT_VERSION="$(release_port_version)"
MSI_VERSION="$(release_msi_version)"
echo "building the $PLATFORM desktop app, version $PORT_VERSION ($CONFIGURATION)"
echo "bundles will be written to $OUT_DIR"

# The version reaches Tauri as a config overlay rather than an edit to
# tauri.conf.json: the committed config would otherwise have to be bumped in
# lockstep with PORT_VERSION, and a release that forgot would ship bundles
# named one version and reporting another.
#
# wix.version is set because WiX requires a numeric major.minor.patch and would
# otherwise derive it from a pre-release string. NSIS has no such field — it
# takes the semver as-is, which is what we want in the installer's own UI.
OVERLAY="$ROOT/desktop/src-tauri/tauri.release.json"
cat >"$OVERLAY" <<JSON
{
  "version": "$PORT_VERSION",
  "bundle": {
    "windows": {
      "wix": {
        "version": "$MSI_VERSION"
      }
    }
  }
}
JSON
trap 'rm -f "$OVERLAY"' EXIT

# Tauri resolves externalBin by appending the host triple, so the daemon has to
# be built and installed under that name before cargo runs.
"$ROOT/scripts/build-daemon-sidecar.sh" "$CONFIGURATION"

cd "$ROOT/desktop"
npm ci

# `npm run tauri --` rather than a global tauri: the CLI is a devDependency, so
# this uses the pinned version rather than whatever the host happens to have.
TAURI_ARGS=(build --bundles "$BUNDLES" --config "$OVERLAY")
[[ "$CONFIGURATION" == debug ]] && TAURI_ARGS+=(--debug)
npm run tauri -- "${TAURI_ARGS[@]}"

# Where cargo put things. CARGO_TARGET_DIR is honoured because the container
# wrapper points it at a cache that outlives the container.
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/desktop/src-tauri/target}"
BUNDLE_DIR="$TARGET_DIR/$CONFIGURATION/bundle"
[[ -d "$BUNDLE_DIR" ]] || {
  echo "error: tauri build left no bundle directory at $BUNDLE_DIR" >&2
  exit 1
}

"$ROOT/scripts/package-desktop.sh" "$BUNDLE_DIR" "$PLATFORM" "$OUT_DIR"
