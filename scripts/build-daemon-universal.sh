#!/usr/bin/env bash
# Build droidectived as a universal (arm64 + x86_64) macOS binary, at
# droidectived/.build/universal/droidectived. Universal like the app: the daemon
# is a sidecar next to it, and an arm64-only binary would break the Intel Macs
# the app itself supports.
#
# Two single-arch builds and a `lipo`, deliberately not one
# `swift build --arch arm64 --arch x86_64`. The multi-arch flag switches SwiftPM
# onto the Xcode build system, and on the release runner's Xcode 16.4 that
# backend cannot read this package's Swift 6 language mode — it calls every
# target's language version unsupported ("given: [6], supported: []"), then
# fails with an empty SWIFT_VERSION and duplicate output files. It happens to
# work on Xcode 26, so a local build gave no warning and the first beta tag was
# the first thing to see it. Each slice here is built by the same native build
# system the Linux and Windows legs use, and `lipo` is already how the bundled
# ffmpeg is made universal.
#
# A script rather than inline YAML so this can be run locally instead of only on
# a tag — which is how it went unnoticed in the first place. The output path is
# fixed rather than printed for the caller to capture: `swift build` logs to
# stdout, so a path on stdout arrives with the whole build log wrapped around
# it. package-daemon.sh fails loudly on a missing binary, so the workflow naming
# the same path cannot silently ship nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/droidectived"
OUT="$PACKAGE/.build/universal/droidectived"

slices=()
for triple in arm64-apple-macosx x86_64-apple-macosx; do
  echo "building droidectived for $triple"
  (cd "$PACKAGE" && swift build -c release --product droidectived --triple "$triple")
  slice="$PACKAGE/.build/$triple/release/droidectived"
  [[ -f "$slice" ]] || {
    echo "error: swift build left no $triple binary at $slice" >&2
    exit 1
  }
  slices+=("$slice")
done

mkdir -p "$(dirname "$OUT")"
lipo -create -output "$OUT" "${slices[@]}"

# Assert both slices are actually in there. `lipo -create` of a single input
# succeeds and writes a *thin* binary, which would ship named "universal" and
# run on nothing but the runner's own architecture.
ARCHS="$(lipo -archs "$OUT")"
for arch in arm64 x86_64; do
  case " $ARCHS " in
  *" $arch "*) ;;
  *)
    echo "error: $OUT has architectures '$ARCHS' — no $arch slice" >&2
    exit 1
    ;;
  esac
done

echo "built $OUT ($ARCHS)"
