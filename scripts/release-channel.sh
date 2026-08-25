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
#   release-channel.sh channel      v3.9.0-beta.1 -> beta
#   release-channel.sh version      v3.9.0-beta.1 -> 3.9.0-beta.1
#   release-channel.sh port-version               -> 0.0.1-beta.1
#   release-channel.sh msi-version                -> 0.0.1
#   release-channel.sh artifacts    v3.9.0-beta.1 -> one filename per line
set -euo pipefail

# Which cross-platform artifacts a beta actually carries today.
#
# Stage 1 ships the daemon: droidectived serves devices, the feature registry,
# action dispatch and the log stream, and builds on all three hosts. It is
# headless — no GUI — so a beta carries it for people driving the daemon
# directly while the Tauri app is built on top.
# Stage 2 adds the Tauri app: a .deb and an .AppImage for Linux, an NSIS
# installer and an MSI for Windows.
CROSS_PLATFORM_STAGE="${CROSS_PLATFORM_STAGE:-2}"

# The Mac and the ports are two version lines. The tag carries the Mac's and
# picks the channel; PORT_VERSION carries the ports'. Reading it here rather
# than in the workflow keeps the "one resolver" property that makes the policy
# testable — see docs/release-channels.md.
RELEASE_CHANNEL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT_VERSION_FILE="${PORT_VERSION_FILE:-$RELEASE_CHANNEL_ROOT/PORT_VERSION}"

# Semver, because Tauri rejects anything else and every bundler derives its own
# version from it. Deliberately strict: a typo here would name every Windows
# and Linux artifact wrongly, and the mistake would only surface after the
# build, sign and notarize steps had run.
readonly PORT_VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$'

# The ports' version: the first non-comment, non-blank line of PORT_VERSION.
release_port_version() {
  local version=""
  [[ -f "$PORT_VERSION_FILE" ]] || {
    echo "error: no PORT_VERSION file at $PORT_VERSION_FILE" >&2
    return 1
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    version="$line"
    break
  done <"$PORT_VERSION_FILE"
  [[ -n "$version" ]] || {
    echo "error: $PORT_VERSION_FILE has no version line" >&2
    return 1
  }
  [[ "$version" =~ $PORT_VERSION_PATTERN ]] || {
    echo "error: '$version' in $PORT_VERSION_FILE is not semver (an underscore is not a pre-release separator; use -beta.1)" >&2
    return 1
  }
  echo "$version"
}

# WiX wants a numeric major.minor.patch, so the MSI drops the pre-release
# suffix. Tauri derives this itself when the field is unset, but it is set
# explicitly at build time so a pre-release version cannot fail the bundler.
release_msi_version() {
  local version
  version="$(release_port_version)" || return 1
  echo "${version%%-*}"
}

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
  local tag="${1-}" channel port
  channel="$(release_channel_for_tag "$tag")" || return 1

  # Both channels: the versioned DMG, plus the stable-named copy that backs the
  # site's permanent /releases/latest/download link. The Mac's version is the
  # tag's.
  echo "Droidective-${tag}.dmg"
  echo "Droidective.dmg"

  [[ "$channel" == beta ]] || return 0
  ((CROSS_PLATFORM_STAGE >= 1)) || return 0

  # Everything below is the ports' own version line, not the tag's.
  port="$(release_port_version)" || return 1

  # The macOS daemon rides the ports' version too: it is the same build of the
  # same program, and naming one copy of it after the Mac app would imply the
  # Mac app and the daemon ship together, which they do not.
  echo "droidectived-${port}-macos-universal.tar.gz"
  echo "droidectived-${port}-linux-x86_64.tar.gz"
  echo "droidectived-${port}-windows-x86_64.zip"

  if ((CROSS_PLATFORM_STAGE >= 2)); then
    # Canonical names, not the bundlers'. Tauri's own output is
    # `Droidective_0.0.1-beta.1_amd64.deb` on one target and
    # `Droidective_0.0.1-beta.1_x64-setup.exe` on another; package-desktop.sh
    # renames them so this list stays the single description of what ships.
    #
    # No .rpm: the bundler can make one, but every name here MUST exist or the
    # release fails, and rpmbuild is a dependency the container does not carry.
    echo "Droidective-${port}-linux-x86_64.deb"
    echo "Droidective-${port}-linux-x86_64.AppImage"
    echo "Droidective-${port}-windows-x86_64-setup.exe"
    echo "Droidective-${port}-windows-x86_64.msi"
  fi

  echo "SHA256SUMS"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1-}" in
  channel) release_channel_for_tag "${2-}" ;;
  version) release_version_for_tag "${2-}" ;;
  port-version) release_port_version ;;
  msi-version) release_msi_version ;;
  artifacts) release_artifacts_for_tag "${2-}" ;;
  *)
    echo "usage: $(basename "$0") {channel|version|artifacts} <tag>" >&2
    echo "       $(basename "$0") {port-version|msi-version}" >&2
    exit 2
    ;;
  esac
fi
