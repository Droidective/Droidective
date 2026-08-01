#!/usr/bin/env bash
# Print the RELEASE_NOTES.md section for a specific tag.
#
# This replaces "take the first ## section", which coupled the file's ordering
# to the release order. That was fine while every tag was the newest thing in
# the file; it breaks as soon as the long-lived beta channel interleaves with
# stable (docs/release-channels.md) — prepare v3.9.0-beta.1's notes, then need a
# v3.8.1 Mac hotfix, and the hotfix silently ships the beta's notes unless you
# remember to shuffle sections around the tag and shuffle them back.
#
# Matching on the heading also turns a missing section into a loud failure
# before anything is signed, instead of a release published with the wrong
# release's notes embedded in its Sparkle appcast item.
#
# Usage: extract-notes.sh <tag> [notes-file]
set -euo pipefail

TAG="${1:?release tag required (e.g. v3.8.0)}"
NOTES="${2:-RELEASE_NOTES.md}"

[[ -f "$NOTES" ]] || {
  echo "error: notes file not found: $NOTES" >&2
  exit 1
}

# Print from the matching heading up to (not including) the next `## `. The
# heading itself is kept: update-appcast.sh strips it for Sparkle, and the
# GitHub release body reads fine with it.
section="$(awk -v want="## Droidective $TAG" '
  $0 == want { found = 1; print; next }
  found && /^## / { exit }
  found { print }
' "$NOTES")"

[[ -n "$section" ]] || {
  echo "error: no '## Droidective $TAG' section in $NOTES" >&2
  echo "       sections present:" >&2
  grep '^## ' "$NOTES" | sed 's/^/         /' >&2
  exit 1
}

printf '%s\n' "$section"
