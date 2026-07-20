---
name: testing
description: Run and write Droidective's ADBKit tests — targeted filters, warnings-as-errors, and the project's standard test kinds (parser, adb arg-vector, registry invariant, canary).
---

# Testing Droidective

## Running

```bash
make test                                    # full ADBKit suite (no Xcode, no device)
cd ADBKit && swift test --filter LogcatParserTests   # one suite while iterating
cd ADBKit && swift test -Xswiftc -warnings-as-errors # what CI actually runs
```

Keep the full suite green before pushing; warnings are build errors in CI.
Device-dependent tests are gated `@Test(.enabled(if:))` on
`MIRROR_LIVE_TEST=1` and skip cleanly otherwise — don't unskip them in CI
paths.

## Writing — the four standard kinds

**Parser test.** Every parser is `static func parseX(_:) -> …`, no I/O —
test it directly with captured output. Always include a CRLF case
(`"\r\n"` is one Swift Character; splitting on `"\n"` silently breaks) and
an empty/malformed/partial-output case.

**Arg-vector test.** Services run through `MockProcessRunner`; assert the
exact adb argument vector in `runner.invocations`. For anything carrying
user input into `adb shell`, assert the `shellQuote`d form appears —
a missing quote is command injection (`OverridesServiceTests` is the
pattern). New action features also add their dispatch case to
`FeatureEngine.implementedIDs` — `everyImplementedActionResolvesToARunner`
and `implementedIDsAreAllRealFeatures` catch omissions and typos.
Cross-platform ids get a `dispatchIOS` case +
`everyIOSCapableActionResolvesToASimctlRunner` coverage.

**Registry invariant.** A rule that spans features is a loop over
`FeatureRegistry.all` (the `everyFeature*` /
`hubsStaySearchableByTheirMembersPrimaryKeyword` pattern), not review
folklore. Adding a feature bumps `hasAll58Features`.

**Behavioral edge test.** Mock only the boundary (`ProcessRunning`,
temp-dir filesystems) — never logic. Trigger every handled error path:
non-zero exit, missing tool, cancelled task.

## Don't regress the guards

- The **16-concurrent-process starvation canary** — process running must
  never block a cooperative thread.
- Mock-driven tests must not stat the real filesystem or assume host facts
  (`/usr/bin/xcrun` exists) — the suite also runs on Linux CI on the port
  branch.
- App-layer note: the AppTests logic bundle compiles `Theme.swift`
  standalone (and links ADBKit for it) — keep that file self-contained.

## Prove a test works

Break the code, confirm the test fails, restore. A test that can't fail is
documentation, not a test.
