#!/usr/bin/env bash
# Rename Tauri's bundle output to the names the release publishes.
#
# Tauri names bundles after the product, the version and the bundler's own idea
# of an architecture: `Droidective_0.0.1-beta.1_amd64.deb` on Linux,
# `Droidective_0.0.1-beta.1_x64-setup.exe` on Windows. Those names encode the
# bundler's conventions rather than ours, they differ per target, and they would
# make `release-channel.sh` describe the artifact set in four dialects.
#
# So the bundlers' names stop here. This script copies each bundle to the one
# canonical name `release_artifacts_for_tag` already promises, which keeps that
# function the single description of what a release contains — the same reason
# package-daemon.sh exists for the daemon.
#
# Exactly one bundle per extension is expected. Two `.deb`s in the same tree
# means a stale build is still lying around, and picking either one at random is
# how a release ships last week's binary.
#
# Usage: package-desktop.sh <search-dir> <linux|windows> <out-dir>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=release-channel.sh
source "$ROOT/scripts/release-channel.sh"

SEARCH_DIR="${1:?a directory to search for bundles is required}"
PLATFORM="${2:?platform required: linux or windows}"
OUT_DIR="${3:?an output directory is required}"

case "$PLATFORM" in
linux) EXTENSIONS="deb AppImage" ;;
windows) EXTENSIONS="exe msi" ;;
*)
  echo "error: unknown platform '$PLATFORM' (expected linux or windows)" >&2
  exit 2
  ;;
esac

[[ -d "$SEARCH_DIR" ]] || {
  echo "error: no such directory: $SEARCH_DIR" >&2
  exit 1
}

PORT_VERSION="$(release_port_version)"
mkdir -p "$OUT_DIR"

# The canonical name for one extension. `-setup.exe` rather than `.exe` because
# NSIS produces an installer, and a bare `Droidective.exe` next to it would read
# as the application binary.
canonical_name() {
  case "$1" in
  deb) echo "Droidective-${PORT_VERSION}-linux-x86_64.deb" ;;
  AppImage) echo "Droidective-${PORT_VERSION}-linux-x86_64.AppImage" ;;
  exe) echo "Droidective-${PORT_VERSION}-windows-x86_64-setup.exe" ;;
  msi) echo "Droidective-${PORT_VERSION}-windows-x86_64.msi" ;;
  *)
    echo "error: no canonical name for a .$1" >&2
    return 1
    ;;
  esac
}

packaged=0
for extension in $EXTENSIONS; do
  # Read into an array the bash-3.2 way: no `mapfile` on macOS or the runner.
  found=()
  while IFS= read -r path; do
    [[ -n "$path" ]] && found+=("$path")
  done < <(find "$SEARCH_DIR" -type f -name "*.${extension}" | sort)

  if ((${#found[@]} == 0)); then
    echo "error: no .$extension bundle under $SEARCH_DIR" >&2
    echo "       the $PLATFORM bundler did not produce one — read the build log" >&2
    exit 1
  fi
  if ((${#found[@]} > 1)); then
    echo "error: ${#found[@]} .$extension bundles under $SEARCH_DIR:" >&2
    printf '         %s\n' "${found[@]}" >&2
    echo "       refusing to guess which one this release should publish" >&2
    exit 1
  fi

  name="$(canonical_name "$extension")"
  cp "${found[0]}" "$OUT_DIR/$name"
  echo "packaged $OUT_DIR/$name"
  echo "     from $(basename "${found[0]}")"
  packaged=$((packaged + 1))
done

echo "packaged $packaged $PLATFORM bundle(s) as version $PORT_VERSION"
