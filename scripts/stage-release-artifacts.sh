#!/usr/bin/env bash
# Collect the artifacts a tag's channel publishes into one directory, and prove
# the set is exactly right before anything is uploaded.
#
# Two failures this exists to prevent:
#
#   1. A stable macOS release shipping Windows or Linux builds. The stable
#      channel is macOS-only (docs/release-channels.md); if a future job forgets
#      its tag gate and leaves a .zip in the build directory, the "unexpected
#      artifact" check fails the release instead of quietly publishing it.
#   2. `fail_on_unmatched_files` failing every stable release. A static upload
#      glob listing Windows artifacts cannot also be correct for a DMG-only
#      release. Staging into one directory lets the publish step glob `dist/*`,
#      and this assertion replaces the glob's weak check with a named one — a
#      missing DMG now fails saying which file is missing.
#
# Usage: stage-release-artifacts.sh <tag> <build-dir> [dist-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=release-channel.sh
source "$ROOT/scripts/release-channel.sh"

TAG="${1:?release tag required}"
BUILD_DIR="${2:?build output directory required}"
DIST_DIR="${3:-dist}"

[[ -d "$BUILD_DIR" ]] || {
  echo "error: build directory not found: $BUILD_DIR" >&2
  exit 1
}

channel="$(release_channel_for_tag "$TAG")"

# Read into an array the bash-3.2 way: macOS (and the macos-15 CI runner) ship
# bash 3.2, which has no `mapfile`.
expected=()
while IFS= read -r line; do
  expected+=("$line")
done < <(release_artifacts_for_tag "$TAG")

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

missing=()
for name in "${expected[@]}"; do
  if [[ -f "$BUILD_DIR/$name" ]]; then
    cp "$BUILD_DIR/$name" "$DIST_DIR/$name"
  else
    missing+=("$name")
  fi
done

if ((${#missing[@]} > 0)); then
  echo "error: $channel release $TAG is missing ${#missing[@]} artifact(s):" >&2
  printf '         %s\n' "${missing[@]}" >&2
  exit 1
fi

# Anything release-shaped that the channel did not ask for is a policy break,
# not a stray file to ignore. Scoped to the artifact prefixes and extensions we
# publish so unrelated build output (.app bundles, dSYMs) stays invisible.
#
# The app bundles are in that scope too: a Linux .deb or a Windows .msi left
# behind by a job that forgot its tag gate is exactly the leak this check exists
# for, and it would be invisible if the patterns only knew about DMGs and daemon
# tarballs.
unexpected=()
while IFS= read -r path; do
  name="$(basename "$path")"
  for want in "${expected[@]}"; do
    [[ "$name" == "$want" ]] && continue 2
  done
  unexpected+=("$name")
done < <(find "$BUILD_DIR" -maxdepth 1 -type f \
  \( -name 'Droidective*.dmg' -o -name 'droidectived-*' -o -name 'SHA256SUMS' \
  -o -name 'Droidective*.deb' -o -name 'Droidective*.AppImage' \
  -o -name 'Droidective*.rpm' -o -name 'Droidective*.msi' \
  -o -name 'Droidective*.exe' \) | sort)

if ((${#unexpected[@]} > 0)); then
  echo "error: $channel release $TAG would publish ${#unexpected[@]} artifact(s) its channel does not allow:" >&2
  printf '         %s\n' "${unexpected[@]}" >&2
  echo "       the stable channel is macOS-only — see docs/release-channels.md" >&2
  exit 1
fi

echo "staged ${#expected[@]} artifact(s) for the $channel release $TAG in $DIST_DIR:"
printf '  %s\n' "${expected[@]}"
