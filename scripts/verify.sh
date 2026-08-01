#!/usr/bin/env bash
# Tiered verification gate. One entry point for the edit→verify loop, ordered
# cheapest-first so a failure surfaces from the fastest tier that can catch it.
#
#   tier 0  static   — ADBKit compiles under -warnings-as-errors
#   tier 1  unit     — ADBKit's swift-testing suite, then the AppTests bundle
#
# Usage: verify.sh [fast|all]
#   fast  tiers 0-1 for ADBKit only — no xcodegen, no Xcode (the inner loop)
#   all   adds the AppTests bundle, which needs a generated project
#
# Quiet on success, verbose on failure: each tier's output goes to a temp log and
# only the failing lines are printed. Keeps a passing run to a few lines.
#
# Both test bundles are swift-testing-only. `xcodebuild test` reports those
# through XCTest's summary as "Executed 0 tests ... TEST SUCCEEDED", so trusting
# that line would pass a bundle that discovered nothing. Every tier here asserts
# a non-zero test count parsed from swift-testing's own summary instead.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-all}"

LOG="$(mktemp -t droidective-verify)"
trap 'rm -f "$LOG"' EXIT

die() {
  echo "error: $*" >&2
  exit 1
}

# Show why a tier failed without dumping a full build log.
dump_failures() {
  echo "─── failing output ───" >&2
  grep -E '✘|error:|warning:|TEST FAILED|Issue recorded|failed after' "$LOG" | head -40 >&2 ||
    tail -40 "$LOG" >&2
}

# swift-testing's summary line: "Test run with 1110 tests in 145 suites passed".
# Emitted by both `swift test` and `xcodebuild test`, so one parser serves both.
test_count() {
  sed -n 's/.*Test run with \([0-9]\{1,\}\) test.*/\1/p' "$LOG" | tail -1
}

# A suite that silently discovers nothing must fail, not pass.
assert_passed() {
  local label="$1" count
  grep -q 'Test run with .* passed' "$LOG" || {
    dump_failures
    die "$label: suite did not report a passing swift-testing run"
  }
  count="$(test_count)"
  [[ -n "$count" && "$count" -gt 0 ]] || die "$label: discovered 0 tests"
  echo "  $label: $count tests passed"
}

tier0_static() {
  echo "── tier 0: static ─────────────────────────────────────────"
  if ! (cd "$ROOT/ADBKit" && swift build -Xswiftc -warnings-as-errors) >"$LOG" 2>&1; then
    dump_failures
    die "tier 0: ADBKit does not compile warning-free"
  fi
  echo "  ADBKit: compiles clean under -warnings-as-errors"
}

tier1_adbkit() {
  echo "── tier 1: unit (ADBKit) ──────────────────────────────────"
  if ! (cd "$ROOT/ADBKit" && swift test) >"$LOG" 2>&1; then
    dump_failures
    die "tier 1: ADBKit suite failed"
  fi
  assert_passed "ADBKit"
}

# The MCP server is its own package (Apple-only; see ReactotronMCP/Package.swift),
# so its suite needs its own run — without this the gate silently loses ~100 tests.
tier1_mcp() {
  echo "── tier 1: unit (ReactotronMCP) ───────────────────────────"
  if ! (cd "$ROOT/ReactotronMCP" && swift test) >"$LOG" 2>&1; then
    dump_failures
    die "tier 1: ReactotronMCP suite failed"
  fi
  assert_passed "ReactotronMCP"
}

tier1_app() {
  echo "── tier 1: unit (AppTests) ────────────────────────────────"
  [[ -d "$ROOT/Droidective.xcodeproj" ]] ||
    die "tier 1: Droidective.xcodeproj missing — run 'make generate' first"
  if ! (cd "$ROOT" && xcodebuild test -project Droidective.xcodeproj -scheme AppTests \
    -destination 'platform=macOS' -derivedDataPath DerivedData \
    CODE_SIGNING_ALLOWED=NO) >"$LOG" 2>&1; then
    dump_failures
    die "tier 1: AppTests bundle failed"
  fi
  assert_passed "AppTests"
}

# `swift test` and `xcodebuild` resolve different graphs into the same committed
# file: SwiftPM writes ADBKit's own pins, Xcode writes the aggregate including the
# app's (Sparkle, Sentry, PostHog, SwiftTerm, KeyboardShortcuts). So running this
# script can leave Package.resolved modified. Report it rather than restoring it —
# silently reverting would also swallow a real dependency change.
warn_resolved_churn() {
  git -C "$ROOT" diff --quiet -- ADBKit/Package.resolved 2>/dev/null && return 0
  echo "note: ADBKit/Package.resolved is modified — the known SwiftPM/Xcode"
  echo "      resolution-scope flip, not a dependency change. Check the diff"
  echo "      before committing: git diff ADBKit/Package.resolved"
}

# Sourceable so the guards above can be unit-tested (see test-verify-guards.sh):
# sourcing defines the functions without running a tier.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "$MODE" in
  fast)
    tier0_static
    tier1_adbkit
    ;;
  all)
    tier0_static
    tier1_adbkit
    tier1_mcp
    tier1_app
    ;;
  *) die "unknown mode '$MODE' (expected 'fast' or 'all')" ;;
  esac

  echo "───────────────────────────────────────────────────────────"
  echo "verify ($MODE): OK"
  warn_resolved_churn
fi
