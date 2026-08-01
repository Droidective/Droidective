#!/usr/bin/env bash
# Resolve a release tag to its channel and to the exact artifact set that
# channel publishes. See docs/release-channels.md for the policy this encodes.
#
# The whole point is that the rule lives in one place. The release job asks this
# script rather than re-deriving "does the tag contain a hyphen" in four steps,
# and test-release-channel.sh unit-tests it — a channel policy that only exists
# as a `contains()` expression scattered through a workflow is one careless edit
# away from publishing Windows builds on the stable macOS channel.
#
# Usage (sourced by the tests, executed by CI):
#   release-channel.sh channel   v3.9.0-beta.1   -> beta
#   release-channel.sh version   v3.9.0-beta.1   -> 3.9.0-beta.1
#   release-channel.sh artifacts v3.9.0-beta.1   -> one filename per line
set -euo pipefail

# Which cross-platform artifacts a beta actually carries today.
#
# Stage 0 ships none: the portable ADBKit core is on main, but droidectived's
# protocol is unimplemented, so there is no Windows or Linux binary worth
# publishing. Raising this to 1 turns the daemon artifacts on — the tests cover
# both values, so the flip is a one-line change with its guard already written.
# Stage 2 (the Tauri app) adds its own entries here.
CROSS_PLATFORM_STAGE="${CROSS_PLATFORM_STAGE:-0}"

# vX.Y.Z, optionally with a pre-release suffix. Anything else is a typo'd tag
# and must not reach a signing step.
readonly RELEASE_TAG_PATTERN='^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$'

release_assert_tag() {
  local tag="${1-}"
  [[ "$tag" =~ $RELEASE_TAG_PATTERN ]] || {
    echo "error: not a release tag: '${tag}' (expected vX.Y.Z or vX.Y.Z-suffix)" >&2
    return 1
  }
}

# stable | beta. A hyphen means pre-release, which means the beta channel —
# the same rule Sparkle's appcast and the GitHub prerelease flag already use.
release_channel_for_tag() {
  local tag="${1-}"
  release_assert_tag "$tag" || return 1
  if [[ "$tag" == *-* ]]; then echo beta; else echo stable; fi
}

# The tag without its leading v, i.e. what MARKETING_VERSION gets.
release_version_for_tag() {
  local tag="${1-}"
  release_assert_tag "$tag" || return 1
  echo "${tag#v}"
}

# Every artifact the release for this tag must publish, one per line. Nothing
# else may ship: stage-release-artifacts.sh rejects extras, which is what keeps
# a stable macOS release free of Windows and Linux builds.
release_artifacts_for_tag() {
  local tag="${1-}" channel version
  channel="$(release_channel_for_tag "$tag")" || return 1
  version="${tag#v}"

  # Both channels: the versioned DMG, plus the stable-named copy that backs the
  # site's permanent /releases/latest/download link.
  echo "Droidective-${tag}.dmg"
  echo "Droidective.dmg"

  [[ "$channel" == beta ]] || return 0
  ((CROSS_PLATFORM_STAGE >= 1)) || return 0

  echo "droidectived-${version}-macos-universal.tar.gz"
  echo "droidectived-${version}-linux-x86_64.tar.gz"
  echo "droidectived-${version}-windows-x86_64.zip"
  echo "SHA256SUMS"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1-}" in
  channel) release_channel_for_tag "${2-}" ;;
  version) release_version_for_tag "${2-}" ;;
  artifacts) release_artifacts_for_tag "${2-}" ;;
  *)
    echo "usage: $(basename "$0") {channel|version|artifacts} <tag>" >&2
    exit 2
    ;;
  esac
fi
