#!/usr/bin/env bash
# Tier 3 of the verification harness: run the device-dependent test suites
# against a real Android emulator, unattended.
#
# The repo already carries live suites (MirrorTransportLive, MirrorSessionLive,
# MirrorPlusRecordLive, ScreenRecorderLive, DeviceLive) gated behind env vars, so
# without a runner they never execute. This boots an emulator, sets the gates,
# runs them, and tears down only what it started.
#
# Usage: emulator-harness.sh [--avd NAME] [--rooted] [--filter SUITE] [--keep] [--record]
#   --avd NAME    boot this AVD instead of the default
#   --rooted      shorthand for the rooted AVD (root-gated features)
#   --filter S    pass a --filter through to swift test (repeatable)
#   --keep        leave a self-booted emulator running afterwards
#   --record      regenerate the committed process fixture from this device
#                 (writes ADBKit/Tests/ADBKitTests/Fixtures/android-emulator.json —
#                 review the diff before committing)
#
# Safety: an emulator that was already attached before this script ran is reused
# and never killed — only a device this script booted gets shut down.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"

DEFAULT_AVD="Medium_Phone_API_35"
ROOTED_AVD="Medium_Tablet_Rooted"
BOOT_TIMEOUT=300

AVD=""
KEEP=0
RECORD=0
FILTERS=()

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --avd)
    AVD="${2:?--avd needs a name}"
    shift 2
    ;;
  --rooted)
    AVD="$ROOTED_AVD"
    shift
    ;;
  --filter)
    FILTERS+=("${2:?--filter needs a suite}")
    shift 2
    ;;
  --keep)
    KEEP=1
    shift
    ;;
  --record)
    RECORD=1
    shift
    ;;
  *) die "unknown argument '$1'" ;;
  esac
done

command -v adb >/dev/null || die "adb not found (looked under $SDK)"
command -v emulator >/dev/null || die "emulator not found (looked under $SDK)"

# Serials of devices present before we touch anything — these are the user's and
# are off-limits for teardown.
preexisting="$(adb devices | awk '/\tdevice$/ {print $1}' | sort)"

BOOTED_SERIAL=""

teardown() {
  if [[ -n "$BOOTED_SERIAL" && "$KEEP" -eq 0 ]]; then
    echo "── shutting down $BOOTED_SERIAL (booted by this run)"
    adb -s "$BOOTED_SERIAL" emu kill >/dev/null 2>&1 || true
  fi
}
trap teardown EXIT

# Poll until the framework is actually up. `wait-for-device` only means adbd
# answered; sys.boot_completed is the real signal.
wait_for_boot() {
  local serial="$1" deadline=$((SECONDS + BOOT_TIMEOUT))
  adb -s "$serial" wait-for-device
  while ((SECONDS < deadline)); do
    if [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')" == "1" ]]; then
      return 0
    fi
    sleep 2
  done
  die "$serial did not finish booting within ${BOOT_TIMEOUT}s"
}

# Reuse an already-attached device when there is one; otherwise boot an AVD.
pick_device() {
  local existing
  existing="$(echo "$preexisting" | grep -v '^$' | head -1 || true)"

  if [[ -n "$existing" && -z "$AVD" ]]; then
    echo "── reusing attached device $existing (not booted by this run)"
    SERIAL="$existing"
    return 0
  fi

  local avd="${AVD:-$DEFAULT_AVD}"
  emulator -list-avds | grep -qx "$avd" || die "AVD '$avd' not found"

  echo "── booting $avd headless"
  emulator -avd "$avd" -no-window -no-audio -no-snapshot -no-boot-anim \
    >/tmp/droidective-emulator.log 2>&1 &

  # Wait for a serial that wasn't there before, so a concurrently-running
  # emulator of the user's is never mistaken for ours.
  local deadline=$((SECONDS + BOOT_TIMEOUT)) new=""
  while ((SECONDS < deadline)); do
    new="$(comm -13 <(echo "$preexisting") \
      <(adb devices | awk '/\tdevice$/ {print $1}' | sort) | head -1)"
    [[ -n "$new" ]] && break
    sleep 2
  done
  [[ -n "$new" ]] || die "no new emulator appeared within ${BOOT_TIMEOUT}s (see /tmp/droidective-emulator.log)"

  BOOTED_SERIAL="$new"
  SERIAL="$new"
  echo "── booted $SERIAL"
}

pick_device
wait_for_boot "$SERIAL"

echo "── device ready: $(adb -s "$SERIAL" shell getprop ro.product.model | tr -d '\r\n')" \
  "(API $(adb -s "$SERIAL" shell getprop ro.build.version.sdk | tr -d '\r\n'))"

# Default to the device suite; the mirror suites need a scrcpy server payload and
# are opt-in via --filter so a missing one doesn't fail the whole run.
if ((${#FILTERS[@]} == 0)); then
  if ((RECORD == 1)); then
    FILTERS=(FixtureRecordingTests)
  else
    FILTERS=(DeviceLiveTests AppBundleInstallLiveTests DeviceTransferLiveTests)
  fi
fi

args=()
for f in "${FILTERS[@]}"; do args+=(--filter "$f"); done

# Exported rather than passed as an `env` array: macOS ships bash 3.2, where
# expanding an empty array under `set -u` is an unbound-variable error, so the
# array form worked with --record and broke without it.
if ((RECORD == 1)); then
  export RECORD_FIXTURES=1
  echo "── recording fixtures (review the JSON diff before committing)"
fi

echo "── running live suites: ${FILTERS[*]}"
set +e
(
  cd "$ROOT/ADBKit" &&
    DEVICE_LIVE_TEST=1 MIRROR_LIVE_TEST=1 MIRROR_SERIAL="$SERIAL" \
      ANDROID_SERIAL="$SERIAL" swift test "${args[@]}"
)
run_status=$?
set -e

if ((run_status != 0)); then
  die "live suites failed (exit $run_status)"
fi

echo "───────────────────────────────────────────────────────────"
echo "emulator harness: OK ($SERIAL)"
