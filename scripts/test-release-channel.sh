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

# The ports' version comes from a fixture, not the repo's PORT_VERSION: these
# assertions name exact filenames, and bumping the real file must not turn this
# suite red. Reading the fixture at all is itself the proof that the file — and
# not the tag — is what names a Windows or Linux artifact.
cat >"$TMP/PORT_VERSION" <<'FIXTURE'
# a comment, and a blank line, both skipped

1.2.3-beta.4
FIXTURE
# Read by the sourced release-channel.sh, which shellcheck cannot see into.
# shellcheck disable=SC2034
PORT_VERSION_FILE="$TMP/PORT_VERSION"

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
for want in droidectived-1.2.3-beta.4-windows-x86_64.zip \
  droidectived-1.2.3-beta.4-linux-x86_64.tar.gz \
  droidectived-1.2.3-beta.4-macos-universal.tar.gz \
  SHA256SUMS; do
  if grep -qxF "$want" <<<"$stage1_beta"; then
    pass "a stage-1 beta publishes $want"
  else
    fail "a stage-1 beta publishes $want" "got: $stage1_beta"
  fi
done

# Stage 1 is the daemon only: the app bundles must not appear a stage early.
if grep -qE '\.(deb|AppImage|msi|exe)$' <<<"$stage1_beta"; then
  fail "a stage-1 beta carries no app bundle" "got: $stage1_beta"
else
  pass "a stage-1 beta carries no app bundle"
fi

stage2_beta="$(CROSS_PLATFORM_STAGE=2 release_artifacts_for_tag v3.9.0-beta.1)"
for want in Droidective-1.2.3-beta.4-linux-x86_64.deb \
  Droidective-1.2.3-beta.4-linux-x86_64.AppImage \
  Droidective-1.2.3-beta.4-windows-x86_64-setup.exe \
  Droidective-1.2.3-beta.4-windows-x86_64.msi \
  droidectived-1.2.3-beta.4-linux-x86_64.tar.gz \
  SHA256SUMS; do
  if grep -qxF "$want" <<<"$stage2_beta"; then
    pass "a stage-2 beta publishes $want"
  else
    fail "a stage-2 beta publishes $want" "got: $stage2_beta"
  fi
done

# The two version lines must not cross. The Mac's version belongs to the DMG
# and nothing else; the ports' version belongs to everything else. A single
# artifact carrying the wrong one is the whole failure mode of this design.
if grep -vE '\.dmg$' <<<"$stage2_beta" | grep -q '3\.9\.0-beta\.1'; then
  fail "the Mac's version never names a port artifact" "got: $stage2_beta"
else
  pass "the Mac's version never names a port artifact"
fi
if grep -E '\.dmg$' <<<"$stage2_beta" | grep -q '1\.2\.3-beta\.4'; then
  fail "the ports' version never names the DMG" "got: $stage2_beta"
else
  pass "the ports' version never names the DMG"
fi

# Raising the stage must never leak the ports onto stable.
for stage in 1 2; do
  stage_stable="$(CROSS_PLATFORM_STAGE=$stage release_artifacts_for_tag v3.8.0)"
  if grep -qiE 'windows|linux|droidectived|\.deb|\.msi|AppImage' <<<"$stage_stable"; then
    fail "stage $stage still keeps stable macOS-only" "got: $stage_stable"
  else
    pass "stage $stage still keeps stable macOS-only"
  fi
done

echo "── the ports' version line ────────────────────────────────"

eq "the version is the first non-comment line" 1.2.3-beta.4 "$(release_port_version)"
eq "the MSI version drops the pre-release suffix" 1.2.3 "$(release_msi_version)"
eq "a plain version needs no stripping" 2.0.0 \
  "$(printf '2.0.0\n' >"$TMP/plain" && PORT_VERSION_FILE="$TMP/plain" release_msi_version)"

# The exact mistake this file's comment warns about: an underscore is not a
# semver pre-release separator, and Tauri rejects it.
printf '0.0.1_beta\n' >"$TMP/underscore"
rejects "an underscore pre-release is rejected" \
  env PORT_VERSION_FILE="$TMP/underscore" "$ROOT/scripts/release-channel.sh" port-version

printf '# only a comment\n' >"$TMP/empty"
rejects "a file with no version line is rejected" \
  env PORT_VERSION_FILE="$TMP/empty" "$ROOT/scripts/release-channel.sh" port-version

rejects "a missing PORT_VERSION file is rejected" \
  env PORT_VERSION_FILE="$TMP/does-not-exist" "$ROOT/scripts/release-channel.sh" port-version

# A beta cannot be named at all without a readable version — better to fail
# here than to publish `droidectived--linux-x86_64.tar.gz`.
rejects "a beta artifact set needs the ports' version" \
  env PORT_VERSION_FILE="$TMP/does-not-exist" "$ROOT/scripts/release-channel.sh" artifacts v3.9.0-beta.1

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

# Same leak, one stage later: the app bundles are the artifacts a stage-2 job
# produces, so each of their extensions has to be visible to the check. A
# pattern list that only knew about DMGs and tarballs would publish these.
for stray in Droidective-1.2.3-beta.4-linux-x86_64.deb \
  Droidective-1.2.3-beta.4-linux-x86_64.AppImage \
  Droidective-1.2.3-beta.4-windows-x86_64.msi \
  Droidective-1.2.3-beta.4-windows-x86_64-setup.exe; do
  : >"$build/$stray"
  rejects "an unexpected ${stray##*.} fails a stable release" stage v3.8.0 "$build" "$TMP/dist"
  rm "$build/$stray"
done

rm "$build/Droidective.dmg"
rejects "a missing artifact fails the release" stage v3.8.0 "$build" "$TMP/dist"

rejects "an absent build directory fails" stage v3.8.0 "$TMP/no-such-dir" "$TMP/dist"

echo "───────────────────────────────────────────────────────────"
if ((failures > 0)); then
  echo "release channel tests: $failures FAILED" >&2
  exit 1
fi
echo "release channel tests: all passed"
