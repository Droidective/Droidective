#!/usr/bin/env bash
# Unit tests for the release channel policy (docs/release-channels.md).
#
# The policy's whole job is to keep Windows and Linux builds off the stable
# macOS channel and to put the right notes in the right release. Both failures
# are invisible until a release is already public and signed, so the rules get
# tested like any other logic — the same reasoning as test-verify-guards.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=release-channel.sh
source "$ROOT/scripts/release-channel.sh"

failures=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  ok   $1"; }
fail() {
  echo "  FAIL $1" >&2
  echo "       $2" >&2
  failures=$((failures + 1))
}

# Assert a function's stdout equals an expected string.
eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected '$expected', got '$actual'"
  fi
}

# Assert a command fails (non-zero) rather than silently accepting bad input.
rejects() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$name" "expected a non-zero exit, got success"
  else
    pass "$name"
  fi
}

echo "── channel resolution ─────────────────────────────────────"

eq "a plain version is stable" stable "$(release_channel_for_tag v3.8.0)"
eq "a beta suffix is beta" beta "$(release_channel_for_tag v3.9.0-beta.1)"
eq "a second beta is still beta" beta "$(release_channel_for_tag v3.9.0-beta.2)"
eq "any pre-release suffix is beta" beta "$(release_channel_for_tag v4.0.0-rc.1)"
eq "a two-digit minor is stable" stable "$(release_channel_for_tag v3.12.0)"

rejects "a tag without the v prefix is rejected" release_channel_for_tag 3.8.0
rejects "a two-component version is rejected" release_channel_for_tag v3.8
rejects "a non-version tag is rejected" release_channel_for_tag vlatest
rejects "an empty tag is rejected" release_channel_for_tag ""
rejects "a tag with a trailing dot is rejected" release_channel_for_tag v3.8.0-
rejects "shell metacharacters are rejected" release_channel_for_tag 'v3.8.0;rm'

eq "version strips the v" 3.8.0 "$(release_version_for_tag v3.8.0)"
eq "version keeps the suffix" 3.9.0-beta.1 "$(release_version_for_tag v3.9.0-beta.1)"

echo "── artifact sets ──────────────────────────────────────────"

eq "a stable release publishes the DMG and its stable-named copy" \
  "Droidective-v3.8.0.dmg
Droidective.dmg" \
  "$(release_artifacts_for_tag v3.8.0)"

# The core requirement: the public macOS channel never carries the ports.
stable_set="$(release_artifacts_for_tag v3.8.0)"
if grep -qiE 'windows|linux|droidectived' <<<"$stable_set"; then
  fail "a stable release carries no Windows or Linux artifact" "got: $stable_set"
else
  pass "a stable release carries no Windows or Linux artifact"
fi

eq "a stage-0 beta is still DMG-only (no daemon binaries exist yet)" \
  "Droidective-v3.9.0-beta.1.dmg
Droidective.dmg" \
  "$(CROSS_PLATFORM_STAGE=0 release_artifacts_for_tag v3.9.0-beta.1)"

stage1_beta="$(CROSS_PLATFORM_STAGE=1 release_artifacts_for_tag v3.9.0-beta.1)"
for want in droidectived-3.9.0-beta.1-windows-x86_64.zip \
  droidectived-3.9.0-beta.1-linux-x86_64.tar.gz \
  droidectived-3.9.0-beta.1-macos-universal.tar.gz \
  SHA256SUMS; do
  if grep -qxF "$want" <<<"$stage1_beta"; then
    pass "a stage-1 beta publishes $want"
  else
    fail "a stage-1 beta publishes $want" "got: $stage1_beta"
  fi
done

# Raising the stage must never leak the ports onto stable.
stage1_stable="$(CROSS_PLATFORM_STAGE=1 release_artifacts_for_tag v3.8.0)"
if grep -qiE 'windows|linux|droidectived' <<<"$stage1_stable"; then
  fail "stage 1 still keeps stable macOS-only" "got: $stage1_stable"
else
  pass "stage 1 still keeps stable macOS-only"
fi

echo "── notes extraction ───────────────────────────────────────"

notes="$TMP/RELEASE_NOTES.md"
cat >"$notes" <<'MD'
## Droidective v3.9.0-beta.1

Beta body.

### A section

- beta bullet

## Droidective v3.8.1

Hotfix body.

## Droidective v3.8.0

Stable body.
MD

extract() { "$ROOT/scripts/extract-notes.sh" "$1" "$notes"; }

# The regression the tag-aware lookup exists for: with a beta sitting at the top
# of the file, a stable hotfix must still get its own notes.
hotfix="$(extract v3.8.1)"
if [[ "$hotfix" == *"Hotfix body."* && "$hotfix" != *"Beta body."* ]]; then
  pass "a hotfix gets its own notes even with a beta above it"
else
  fail "a hotfix gets its own notes even with a beta above it" "got: $hotfix"
fi

if [[ "$hotfix" != *"Stable body."* ]]; then
  pass "extraction stops at the next section"
else
  fail "extraction stops at the next section" "leaked the following section"
fi

beta_notes="$(extract v3.9.0-beta.1)"
if [[ "$beta_notes" == *"beta bullet"* && "$beta_notes" != *"Hotfix body."* ]]; then
  pass "a beta gets its own notes, ### subsections included"
else
  fail "a beta gets its own notes, ### subsections included" "got: $beta_notes"
fi

eq "the heading is kept" "## Droidective v3.8.0" "$(extract v3.8.0 | head -1)"
rejects "a tag with no section fails loudly" extract v9.9.9
rejects "a missing notes file fails loudly" "$ROOT/scripts/extract-notes.sh" v3.8.0 "$TMP/nope.md"

echo "── artifact staging ───────────────────────────────────────"

build="$TMP/build"
mkdir -p "$build"
stage() { "$ROOT/scripts/stage-release-artifacts.sh" "$@" >/dev/null 2>&1; }

: >"$build/Droidective-v3.8.0.dmg"
: >"$build/Droidective.dmg"
if stage v3.8.0 "$build" "$TMP/dist"; then
  pass "a complete stable set stages"
else
  fail "a complete stable set stages" "expected success"
fi
eq "only the expected files are staged" "Droidective-v3.8.0.dmg
Droidective.dmg" "$(cd "$TMP/dist" && ls)"

# A Windows artifact left behind by an ungated job must fail the stable release,
# not ride along with it.
: >"$build/droidectived-3.8.0-windows-x86_64.zip"
rejects "an unexpected Windows artifact fails a stable release" stage v3.8.0 "$build" "$TMP/dist"
rm "$build/droidectived-3.8.0-windows-x86_64.zip"

rm "$build/Droidective.dmg"
rejects "a missing artifact fails the release" stage v3.8.0 "$build" "$TMP/dist"

rejects "an absent build directory fails" stage v3.8.0 "$TMP/no-such-dir" "$TMP/dist"

echo "───────────────────────────────────────────────────────────"
if ((failures > 0)); then
  echo "release channel tests: $failures FAILED" >&2
  exit 1
fi
echo "release channel tests: all passed"
