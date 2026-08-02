#!/usr/bin/env bash
# Rename the bundles `tauri build` produced to the names the channel publishes.
#
# A script rather than inline YAML, for the same reasons as package-daemon.sh:
# the naming lives next to the policy release-channel.sh asserts against, and a
# packaging change can be run locally instead of only on a tag.
#
# Tauri names its output after the product and its own version scheme
# (`Droidective_3.9.0_amd64.deb`, `Droidective_3.9.0_x64-setup.exe`), which
# differs per bundle type and does not say which platform a file is for once
# it sits next to its siblings in one release. Everything is renamed to the
# daemon's scheme — `<product>-<version>-<platform>.<ext>` — so a release page
# reads consistently.
#
# Usage: package-desktop.sh <version> <platform> <bundle-dir> <out-dir>
#   version     3.9.0-beta.1   (no leading v)
#   platform    linux-x86_64 | windows-x86_64
#   bundle-dir  desktop/src-tauri/target/release/bundle
#   out-dir     where the renamed artifacts land
set -euo pipefail

VERSION="${1:?version}"
PLATFORM="${2:?platform}"
BUNDLE_DIR="${3:?bundle dir}"
OUT_DIR="${4:?out dir}"

case "$PLATFORM" in
linux-x86_64 | windows-x86_64) ;;
*)
  echo "error: unknown platform '$PLATFORM'" >&2
  exit 1
  ;;
esac

[[ -d "$BUNDLE_DIR" ]] || {
  echo "error: no bundle directory at $BUNDLE_DIR" >&2
  exit 1
}

mkdir -p "$OUT_DIR"

# Exactly one match, or fail. A glob that quietly picks the first of two
# bundles would publish an arbitrary one of them.
take() {
  local pattern="$1" extension="$2"
  local -a found=()
  while IFS= read -r line; do found+=("$line"); done < <(
    find "$BUNDLE_DIR" -type f -name "$pattern" | sort
  )
  if [[ ${#found[@]} -ne 1 ]]; then
    echo "error: expected exactly one $pattern under $BUNDLE_DIR, found ${#found[@]}" >&2
    printf '  %s\n' "${found[@]}" >&2
    return 1
  fi
  local destination="$OUT_DIR/Droidective-${VERSION}-${PLATFORM}.${extension}"
  cp "${found[0]}" "$destination"
  echo "packaged $(basename "$destination")"
}

if [[ "$PLATFORM" == linux-x86_64 ]]; then
  # Both: the .deb for Debian and Ubuntu, where it pulls adb in as a
  # dependency, and the AppImage for everything else.
  take '*.deb' deb
  take '*.AppImage' AppImage
else
  # NSIS rather than the MSI: it installs per-user, so a beta tester does not
  # need an administrator to try it.
  take '*-setup.exe' exe
fi
