#!/usr/bin/env bash
# Unit tests for verify.sh's own guards. A verification harness that reports
# success on a suite which ran nothing is worse than no harness, so the guards
# get tested like any other logic.
#
# The case that motivates this: swift-testing prints
#   "Test run with 0 tests in 0 suites passed"
# for a run that discovered nothing. Grepping for "passed" would accept it; only
# the non-zero count assertion rejects it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=verify.sh
source "$ROOT/scripts/verify.sh"

failures=0

check() {
  local name="$1" expected="$2" fixture="$3"
  printf '%s' "$fixture" >"$LOG"
  local actual=pass
  # assert_passed exits on failure, so run it in a subshell.
  (assert_passed "probe" >/dev/null 2>&1) || actual=fail
  if [[ "$actual" == "$expected" ]]; then
    echo "  ok   $name (expected $expected)"
  else
    echo "  FAIL $name — expected $expected, got $actual" >&2
    failures=$((failures + 1))
  fi
}

echo "── verify.sh guard tests ──────────────────────────────────"

check "a real passing run is accepted" pass \
  'Test run with 1110 tests in 145 suites passed after 4.797 seconds.'

check "zero-discovery run is REJECTED despite saying passed" fail \
  'Test run with 0 tests in 0 suites passed after 0.001 seconds.'

check "a failing run is rejected" fail \
  'Test run with 1111 tests in 146 suites failed after 4.769 seconds with 1 issue.'

check "XCTest-only summary with no swift-testing line is rejected" fail \
  'Executed 0 tests, with 0 failures (0 unexpected) in 0.000 seconds
** TEST SUCCEEDED **'

check "empty output is rejected" fail ''

check "a single test is accepted" pass \
  'Test run with 1 test in 1 suite passed after 0.01 seconds.'

echo "───────────────────────────────────────────────────────────"
if ((failures > 0)); then
  echo "guard tests: $failures FAILED" >&2
  exit 1
fi
echo "guard tests: all passed"
