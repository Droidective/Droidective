# Handoff: verification harness + portable ADBKit core

Written 2026-07-25. Everything done in one working session, the state it left
behind, and how to pick it up on another machine.

Read §1 and §2 first. §3 is machine setup. §11 is the literal resume procedure.

---

## 1. Where things stand

**Done and verified in CI:**

- A tiered verification harness that runs and judges itself, no human in the loop.
- ADBKit's full test suite **passes on Linux**.
- ADBKit **compiles on Windows**.
- Six review findings fixed, each as its own PR.
- One startup crash found and fixed.

**Not done, deliberately:** the Linux and Windows *apps*. What landed is the
shared core (Phase 0). The apps need the daemon and web UI — Phases 1–4,
estimated 8–27 working sessions. See §10.

**Test counts now:** 1167 ADBKit + 67 AppTests (was 1110 + 65).

**Everything is on two branches, both green, neither merged:**

| PR | Branch | Base | Size |
| --- | --- | --- | --- |
| #224 | `feat/verification-harness` | `main` | +3572/−263 |
| #225 | `feat/windows-ci` | `feat/verification-harness` | +32/−2 |

`main` was at `8df3709` when this work branched and had not moved as of writing.

---

## 2. What to do first

**Merge #224, then #225.** From a browser — it doesn't need a Mac.

#224 already contains merges of #219–#223, so those close automatically. #225 is
stacked on #224 and must go second.

**Why it's time-sensitive:** #224 is 3,572 lines and includes a merge of
`feat/cross-platform-core`, which had drifted 88 commits behind `main` before
this session and cost real time to reconcile. Every commit landing on `main`
raises the conflict odds on a branch four times that size.

**Two decisions to confirm while reviewing** — both flagged in the PR body:

1. `ADBKit/Package.resolved` now holds ADBKit's own resolution instead of the
   aggregate Xcode was writing into it. Revert that one file if you disagree;
   nothing else depends on it.
2. #222 edited `CLAUDE.md` to move the pane mapping from `[silent]` to `[test]`.
   Correct, but reword if you'd rather.

---

## 3. Setting up another Mac

### Required

```bash
brew install xcodegen gitleaks prek shellcheck shfmt actionlint
prek install                      # activates the gitleaks pre-commit hook
```

Xcode with a Swift 6.3 toolchain, and the Android SDK at
`~/Library/Android/sdk` (or `ANDROID_SDK_ROOT`/`ANDROID_HOME` set).

Versions this session ran against:

| tool | version |
| --- | --- |
| Swift | 6.3.3 |
| XcodeGen | 2.45.4 |
| gitleaks | 8.30.1 |
| prek | 0.4.11 |
| shellcheck | 0.11.0 |
| adb | 1.0.41 |
| Node | `.nvmrc` pins 22; this machine had 20.14.0 as its global default |

### Not required, but limits what you can run

- **Two AVDs** named `Medium_Phone_API_35` and `Medium_Tablet_Rooted`. The
  emulator harness defaults to the first and uses the second for root-gated
  features. Any AVD works via `--avd NAME`.
- **A local Linux runtime** for `make test-linux`. Apple's `container` CLI needs
  `container system start` plus `container system kernel set --recommended`.
  **That kernel download timed out on this machine and the Docker daemon was
  down, so local Linux was never working here — CI was the Linux gate all
  session.** Don't assume `make test-linux` runs out of the box.

### Gotchas that will bite on a fresh machine

- **`prek install` is not done by cloning.** Before this session the repo had
  `.pre-commit-config.yaml` declaring a gitleaks hook, `prek` was not installed,
  and `.git/hooks/` held only samples — so the secret-scanning gate CLAUDE.md
  describes **was not actually running**. Verify with a fake credential; note
  that gitleaks *allowlists* AWS's documented `AKIAIOSFODNN7EXAMPLE` pair, so
  test with a `ghp_`-shaped string instead.
- **`.env.telemetry` absence used to crash the app on launch.** Fixed in #223. If
  you're on a commit before that, a keyless build dies at `Telemetry.swift:80`.
- **`swift test` rewrites `ADBKit/Package.resolved`.** SwiftPM resolves ADBKit's
  own pins; Xcode writes the aggregate including the app's. Never commit that
  churn — `git checkout -- ADBKit/Package.resolved` before committing. `verify.sh`
  prints a note when it happens.

---

## 4. The harness

One entry point per tier, ordered cheapest-first.

| tier | command | covers | time |
| --- | --- | --- | --- |
| 0 static | `make verify-fast` | ADBKit under `-warnings-as-errors` | ~4s |
| 1 unit | `make verify` | ADBKit suite + AppTests bundle | ~25s |
| — guards | `make verify-self` | the harness's own assertions | <1s |
| 3 device | `make test-emulator` | ADBKit services against a real emulator | ~25s |
| 3b replay | (inside tier 1) | parsers against recorded real device output | — |
| 4a launch | `make test-smoke` | the built app actually comes up | ~15s |
| 6 mutation | `make test-mutation` | the suite goes red when code breaks | ~40s |
| linux | `make test-linux` | the same ADBKit suite on Linux | container |

Also: `make test-app` (AppTests alone), `make test-emulator-rooted`,
`make test-emulator-mirror`, `scripts/emulator-harness.sh --record`.

### 4.1 `scripts/verify.sh` — tiers 0 and 1

Quiet on success, prints only failing lines otherwise, so a passing run is a few
lines and a failing one shows the cause without a full build log.

**The load-bearing detail:** both test bundles are swift-testing-only, so
`xcodebuild test` reports them through XCTest as
`Executed 0 tests ... TEST SUCCEEDED`. Trusting that line would pass a bundle
that discovered nothing. Every tier therefore parses swift-testing's own summary
(`Test run with N tests ... passed`) and asserts N > 0.

That guard has its own unit tests (`scripts/test-verify-guards.sh`, 6 cases),
including the one that motivated it: a zero-discovery run prints
`Test run with 0 tests in 0 suites passed` — the word "passed" is right there.

`verify.sh` is sourceable (`BASH_SOURCE` guard at the bottom) so those guards can
be tested without running a tier.

### 4.2 `scripts/emulator-harness.sh` — tier 3

Boots an AVD headless, waits for `sys.boot_completed` (not just
`wait-for-device`, which only means adbd answered), runs the live suites, tears
down.

**Safety property:** it snapshots attached serials before doing anything and
tears down **only** a device it booted. An emulator you were already using is
reused and left alone. Verified both directions — reused `emulator-5554`
untouched while a self-booted `emulator-5556` was killed.

It also gives the repo's four pre-existing live suites a runner. `MirrorTransportLive`,
`MirrorSessionLive`, `MirrorPlusRecordLive` and `ScreenRecorderLive` were gated
behind `MIRROR_LIVE_TEST=1` with nothing to set it, so they almost certainly
never ran. `make test-emulator-mirror` runs them.

### 4.3 `DeviceLiveTests` — 7 tests against a real device

Every assertion is deterministic: a property Android always defines, or a marker
the test plants itself. Notably `logcatDumpContainsAPlantedMarker` writes a UUID
via `adb shell log` and then asserts it comes back parsed — no hoping the device
was chatty.

### 4.4 The fixture recorder — tier 3b

`RecordingProcessRunner` wraps a real runner and captures invocations;
`FixtureProcessRunner` replays them. Both live in the test target, so the shipping
library carries no recording machinery.

Committed recording: `ADBKit/Tests/ADBKitTests/Fixtures/android-emulator.json`,
14 entries / ~74 KB from a real Pixel-class emulator (Android 15, SDK 35).
`RecordedOutputParserTests` replays it **with no device attached**, so parsers
face genuine `getprop` (31 KB of it), `ls -la`, threadtime `logcat`, `ps`,
`/proc/meminfo` and `dumpsys battery` in CI and on Linux.

Three design problems hit and solved, each of which would have made the fixtures
useless:

1. **The serial was baked into recorded argv.** adb targets with `-s <serial>`,
   so a raw recording fails to match on a host where the emulator took another
   port. Recorder and replayer now normalise `-s <serial>` → `<serial>`
   identically. There's a test proving a fixture recorded on `emulator-5554`
   drives `emulator-5556`.
2. **Two privacy leaks.** The recorded executable was the full adb path
   (containing the developer's home directory) and stdout can carry home paths.
   Both scrubbed *at record time*, so an unredacted value is never written.
   Also scrubbed: IPv4, MACs, the serial. Commands whose whole output is the
   secret (Wi-Fi credential stores, any `su -c`) are never recorded at all.
   Binary and oversized payloads are kept as metadata only — the 1.1 MB
   `dumpsys package packages` shows as `over cap, 1110862 bytes`.
3. **The generator invented argv instead of calling services.** Recording plain
   `ps -A` produced output the process-name parser correctly rejects, because
   `LogcatStreamer` actually sends `ps -A -o PID,NAME`. The generator now drives
   real service methods so recorded argv is production argv by construction.

**To regenerate:** `scripts/emulator-harness.sh --record`, then review the JSON
diff. Don't hand-edit it.

An unmatched invocation returns a non-zero exit and a reason rather than empty
output — a silent empty stdout is how a parser test passes for the wrong reason.

### 4.5 `scripts/mac-smoke.sh` — tier 4a

Launches the built app, confirms it survives a settle period, polls for a window
in the accessibility tree, screenshots.

Guards against the three ways this test could lie:

- **pkills first**, because `open` re-activates a stale instance rather than
  launching the new build.
- **Compares process start time against the binary's mtime**, so a surviving
  instance can't make it pass against old code.
- **Refuses a bundle with no `Droidective.debug.dylib`**, which is what a Release
  build staged over the Debug path by Sparkle looks like.

**It found a real crash on its first run** (§6.6).

**Known limitation:** it needs an unlocked display. A locked or sleeping Mac
reports zero windows to System Events and makes `screencapture` return black.
It detects this via `IOConsoleLocked` and stops after the liveness check rather
than reporting a false failure.

### 4.6 `scripts/mutation-gate.sh` — tier 6

Breaks real code one mutation at a time and asserts `swift test` **fails** for
each. A survivor is reported as a coverage gap and fails the run.

Five mutations, weighted to what this codebase treats as load-bearing:

| mutation | simulates |
| --- | --- |
| `shellQuote` returns its input | command injection via any user value |
| `shellQuote` stops escaping embedded quotes | quote-break escape |
| device list splits on `"\n"` only | CRLF output parsed as one line |
| `PaneSplit.clampedFraction` returns raw | split fraction unclamped |
| `WindowEffects.clamped` returns raw | out-of-range opacity reaches renderer |

All five are currently killed. Verified in **both** directions — a control
whitespace-only mutation was correctly reported as SURVIVED with exit 1.

Its precondition checks only the files it mutates, not all of ADBKit, because
`Package.resolved` churn would otherwise block every run after any prior test.

---

## 5. Verifying the harness itself

Every tier was proven by seeded breakage rather than assumed:

- **Tier 0** — planted an unused-variable warning → exit 1.
- **Tier 1** — planted a failing test → exit 1, naming the test.
- **Tier 1 guards** — 6 unit tests, including the zero-discovery case.
- **Tier 3** — planted a failing live test against the real emulator → exit 1.
- **Tier 3b** — 17 unit tests over the recorder: redaction, denied commands,
  binary/oversized payloads, cross-device replay.
- **Tier 4a** — found a real crash unaided.
- **Tier 6** — both directions, as above.
- **Portability guard** — scratch file importing `Network` fails it; gated
  import doesn't.
- **Secret gate** — a fake GitHub PAT blocked an actual `git commit`.

---

## 6. Review findings and fixes

Found by reading the code against CLAUDE.md's own conventions. Three initial
leads were **false positives that reading the code killed** — recorded in §6.7,
because a review that reports everything it greps isn't a review.

### 6.1 ffmpeg errors lost to progress spam — PR #220

`VideoEditService.swift:84` and `ScreenRecorder.swift:190` built the user-facing
failure message from `stderrText.split(separator: "\n").suffix(3)`.

**ffmpeg separates progress updates with `\r`, not `\n`**, so the final chunk was
the entire progress blob and `suffix(3)` returned that instead of the error. This
degraded exactly the message you need when an export fails.

Fixed with a shared `VideoEditing.stderrTail` using `.components(separatedBy:
.newlines)` plus a blank filter. 8 new tests; 5 of them fail without the fix.

Also established: `"a\r\nb\r\n".split(separator: "\n")` returns **one element**,
so on CRLF the old "last 3 lines" was the entire dump up to the 4 MiB cap. These
were the only two `split(separator: "\n")` sites in the repo.

### 6.2 Stale writes from cancelled tasks — PR #219

CLAUDE.md requires guarding `!Task.isCancelled` before writing fetched results
into `@State`. 24 of 29 files did; four didn't:
`DeepLinksView.loadLinks`, `FridaConsoleView.refresh`,
`RecordingDecision.loadThumbnail`, `VideoEditorPane.loadAsset`.

Failure: switch selection A → B quickly; if A's await resolves after B has
written, A's stale data lands last. Self-correcting, so it presents as an
intermittent glitch.

**`DeviceBarView` was in my original finding and I was wrong.** Its writes happen
inside `AppState+Emulators.swift`, so a guard in the view closure would only skip
the *second* call — the first write has already landed. The data is host-wide
(which AVDs are installed), not selection-scoped, so the stale-pane symptom
doesn't exist. And four other writers hit that state from unstructured `Task {}`
where `Task.isCancelled` is always false. Left unchanged deliberately.

No test: these are private methods on `View` types reading `@Environment`, and
driving `.task(id:)` cancellation from a unit test would need each loader
extracted into an injectable type. The PR says so rather than inventing one.

### 6.3 Portability rule had no enforcement — PR #221

CLAUDE.md forbids new Apple-only imports in ADBKit outside the already-Apple-bound
subsystems. Nothing enforced it, and CI only built macOS.

`PortabilityGuardTests` now scans ADBKit and fails on an Apple-only import or a
corelibs trap not inside a matching `#if canImport(...)` gate. Matching is
**per-module**, so a `canImport(os)` gate can't launder an `import Network`
inside it, and `#else` / `#if DEBUG` / `#if os(macOS)` / `#if !canImport` exempt
nothing.

Traps covered: `OSAllocatedUnfairLock`, `NSDataDetector`,
`FileManager.replaceItemAt`, `posix_spawn`, and `FileHandle.bytes` (matched only
on a line also containing `await` or `.lines`). Deliberately skipped:
`readabilityHandler`-as-EOF, because no text pattern separates misuse from the
mandated correct use and it would only cry wolf.

**Two corrections to my original finding:** `McpHTTPListener.swift` was *not*
debt — its `import os` was already `canImport(os)`-gated. And I'd only grepped
imports, so I missed four trap-only files with no Apple import at all
(`JSONStore`, `EmulatorService`, `LogcatStream`, `SimulatorLogStream`).

**The allowlist is now empty.** The portable-core merge gated every entry it
excused, and a companion test fails on a stale entry, so it can't silently
refill.

### 6.4 detailByKind contract unguarded — PR #222

A `.view` feature in `implementedIDs` but missing from `detailByKind` renders
"Coming Soon" with no build or test failure. CLAUDE.md marks it `[silent]`.

The invariant *held* — this is preventive. The fix is better than what I briefed:
instead of a static id array beside the switch (a second list that can drift), a
`String`-backed `CaseIterable` enum `FeatureDetailRoute` with an **exhaustive
switch and no `default`**, so a route without a pane is a *compile* error. The
test only has to enforce route ↔ registry.

**Verified behaviour-preserving mechanically:** 39 ids before, 39 after,
identical id → view mapping, none added, removed, or changed.

### 6.5 Toolchain drifts

`.nvmrc` pins Node 22 (CI used 22, local had no pin). And prek was installed and
the gitleaks hook activated — see §3.

### 6.6 Startup crash in keyless builds — PR #223

`Telemetry.swift:80` read `NSApp.isActive` from `trackAppActivity()`, reached
unconditionally from `ADTApp.init():233`. **`NSApp` is nil during SwiftUI's
`App.init()`**, so the implicit unwrap traps:

```
Telemetry.swift:80: Fatal error: Unexpectedly found nil while implicitly
unwrapping an Optional value
```

**Only affects builds without telemetry keys.** `Telemetry.start()` calls
`startSentry()` first, and with a real DSN `SentrySDK.start` touches
`NSApplication`, which creates the instance and populates `NSApp`. Release builds
get CI-injected keys, so shipped users were never affected.

Fixed with `NSApp?.isActive ?? false`. Verified `didBecomeActiveNotification`
fires ~1s later so the flag isn't stuck false.

**Why CI missed it:** the `build` job passes **no** keys (`ci.yml:36`), so it
compiles exactly the crashing configuration and never launches it; `release`
passes the secrets. A coverage-shape problem, not a code-review one.

**I initially misdiagnosed this as a broken shipped release** and escalated
before checking the one variable that mattered. See §9.

### 6.7 Checked and clean

- **`shellQuote`: no injection found.** Every `su -c` site traced end-to-end.
  `FileExplorerService:23` looks wrong (joins argv with spaces, quotes the whole
  line) but is correct: callers quote inner values, `runShell` quotes the outer,
  so `su -c` gets one argument the inner shell re-splits properly — a path with
  spaces works. `WifiService:115` reads from a static `configStorePaths` list,
  Frida's path is a `static let`, `RestrictionsService` interpolates a `Bool`.
- **No feature-wide `.onDrop`** catch-alls; all scoped to specific UTIs and rows.
- **No opaque full-pane fills** blocking translucency — the `Color.black` hits
  are video/mirror backgrounds where black is correct, or overlays with explicit
  opacity.
- **`.task(id:)` readiness keys correct** where it matters: `targetSerials` is
  `devices.filter(\.isReady)`.

### 6.8 Still open

**`ManagedToolStore` hardcodes `/usr/bin/unzip` and `/usr/bin/tar`**, violating
CLAUDE.md's no-host-paths rule, with no guard. Needs a different check
(host-path literal scanning) and a judgement call, since `HostArchive` already
picks extraction commands per host. Bundle it with Phase 2.

---

## 7. The cross-platform work

Merged `feat/cross-platform-core` (88 commits behind `main`). The merge itself
conflicted in only 4 files, but the *combination* exposed five blockers that
branch never hit, because it predates code added to `main` afterwards.

### 7.1 Linux blockers

1. **ReactotronMCP referenced gated types.** It uses `ReactotronServer` /
   `ReactotronService`, which the port gates behind `#if canImport(Network)`, so
   `swift test` could not build the package on Linux at all. That target serves
   the Network.framework relay's data, so it's genuinely Apple-only until the
   listener moves to NIO. Gated the whole target (18 files) the same way — off
   Apple the module exposes nothing. No effect on macOS.
2. **`FileManager.createFile` is `@discardableResult` on Darwin only.** Nine
   test-setup calls compiled silently on macOS and were warnings on Linux, where
   warnings are errors.

### 7.2 Windows blockers

3. **BoringSSL vs MSVC STL.** `windows-2025` ships MSVC 14.51, whose
   `yvals_core.h` hard-errors with `STL1000: Unexpected compiler version,
   expected Clang 20 or newer`. Swift 6.2.4 bundles an older clang and
   swift-crypto vendors BoringSSL as C/C++, so the assert fires compiling
   BoringSSL, not our Swift. **Pinned `windows-2022`.** Revisit when a Swift
   release ships clang 20+ — pinning an old image is maintenance debt.
4. **`kill` / `SIGKILL` don't exist on Windows.** Both escalation paths in
   `SystemProcessRunner` (timeout watchdog and cancellation handler) failed.
   Gated with `#if !os(Windows)` so Darwin and Linux are byte-identical.
   Windows needs none of it: Foundation maps `terminate()` to `TerminateProcess`,
   already the forceful kill.
5. **`inet_pton` and `pid_t`.** `ConnectionService` validated IPv6 with
   `inet_pton` (`in6_addr`, `AF_INET6` are POSIX-only) — replaced with a
   hand-written grammar check plus 7 tests pinning it (8-group form, compressed
   forms including bare `::`, dotted-quad tails, wrong counts, double
   compression, stray colons, over-long and non-hex groups, zone indices).
   `pid_t` → `Int32`; same type on POSIX, absent on Windows.

Also: `--build-tests` can't be used on Windows because it builds ReactotronMCP →
swift-nio, whose Windows support is partial (UDS/UDP/pipe channels unsupported,
`NIOFileSystem` stubbed with `fatalError`, apple/swift-nio#3647 blocks downstream
packages on Swift 6.1+). The job builds `--target ADBKit` and
`--target ADBKitTests` explicitly.

**Windows tests are compiled, not run** — the process-spawning tests still assume
POSIX paths. Separate audit.

### 7.3 Merge resolutions worth re-reading

- **`ADBKit/Package.swift`** — git merged both `dependencies:` blocks *without a
  conflict marker*, producing invalid Swift. Resolved by hand into one array
  (swift-sdk, swift-nio, swift-crypto) with Crypto conditional on Linux/Windows.
  Watch for this if you ever re-merge.
- **`ADBKit/Package.resolved`** — regenerated from the merged manifest.
- **`ADBKitTests` excludes `Fixtures`** — read via `#filePath`, not a bundle, so
  SwiftPM was warning about unhandled files.

---

## 8. macOS impact

The constraint was zero impact on existing Mac users. Evidence, not assertion:

- **`FeatureDetailView`** is the only large App change (172 lines) and is a pure
  refactor — 39 ids before and after, identical mapping (§6.4).
- Everything else in `App/Sources` is a bug fix: four cancellation guards, one
  `NSApp` optional-chain.
- Every `#if os(Windows)` branch is a no-op on macOS. `SystemProcessRunner`'s
  Darwin path is byte-identical — `#if !os(Windows)` was chosen specifically so
  no working platform changes.
- macOS CI green throughout (`test` + `build`).
- Local: mutation 5/5, device suite 7/7 against a real emulator, app launches and
  renders (screenshot verified — Device Info against a live emulator).

---

## 9. Mistakes made this session

Recorded because they're the kind that repeat.

1. **Misdiagnosed the launch crash as a broken shipped release.** I tested four
   combinations (Debug/Release × direct-exec/`open`) and concluded I'd been
   thorough — but all four shared one hidden variable: no `.env.telemetry`. I'd
   read the Makefile block early and knew release builds get keys injected, and
   still didn't vary it. Testing four values of the wrong axes isn't
   thoroughness. The tell was there too: a launch-blocking bug surviving a
   release is implausible enough that it should have sent me hunting for what
   differed. **Ask the user to try the shipped build before escalating.**
2. **`git reset --hard` destroyed an uncommitted WIP edit.** Recovered exactly
   from prek's saved patch (`~/.cache/prek/patches/`), but it was gone for ~30
   minutes and I only noticed while tidying. **Check the working tree after
   every destructive git command, not at the end.**
3. **Output grepping hid a harness failure.** `emulator-harness.sh` was broken on
   every run without `--record` (macOS bash 3.2 errors on empty-array expansion
   under `set -u`), but I was filtering output for success strings instead of
   checking exit codes, so it looked fine. All five scripts now parse under
   `/bin/bash` 3.2.
4. **`mac-smoke.sh` had two false-failure modes** — checking for a window once
   after a fixed settle, and failing outright on a locked display.

---

## 10. Roadmap

Estimates in working sessions, from the approved plan and partly validated by
this session's throughput (Phase A + Phase 0 + 6 fix PRs in one).

| phase | work | sessions | blocked on |
| --- | --- | --- | --- |
| A | verification harness | — | **done** |
| 0 | portable core, Linux green, Windows compiling | — | **done** |
| 1 | `droidectived` — stdio JSON-RPC daemon | 3–5 | merges |
| 2 | portability follow-ups | 2–3 | — |
| 3a | WebKitGTK spike (a **gate**) | 1–2 | **a Linux desktop** |
| 3b | web UI | 15–23 | 3a |
| 4 | Windows packaging | 3–5 | **signing certificate** |

**Linux usable ≈ 8–12 cumulative sessions; Linux parity ≈ 20–27; Windows +3–5.**

### Do Phase 1 next

The stdio JSON-RPC daemon. New `.executable` product, NDJSON on stdin/stdout,
`FeatureRegistry.all` emitted as JSON so a UI renders the schema rather than
hardcoding 59 features, streams as notifications, golden contract test in the
`McpGoldenContractTests` style.

Three reasons it comes first: it's the seam the web UI, an iOS companion and
remote debugging all need; it pays off even if Linux/Windows never ship (it
generalises the MCP server from Reactotron-only to everything ADBKit can do); and
it needs no Linux desktop and no certificate.

**Show the protocol shape before building it out** — it's an interface
commitment.

### Why stdio and not localhost HTTP

The original port doc proposed HTTP + WebSocket with a token file. stdio sidesteps
the hardest blocker: swift-nio's Windows support is partial and #3647 blocks
downstream packages on Swift 6.1+. Tauri supports stdio natively
(`bundle.externalBin` + `app.shell().sidecar()`). No port, no token file, no
loopback bind, no firewall prompt. A Rust HTTP proxy can add the remote story
later with zero Swift sockets.

### Two long-lead items to start now

1. **Windows Authenticode / Azure Trusted Signing certificate.** The only
   roadmap item whose lead time isn't engineering — org validation takes days to
   weeks. Blocks shipping Phase 4.
2. **A Linux desktop reachable by SSH or VNC.** Gates 3a and materially slows 3b.
   CI proves compilation, not whether the UI feels right.

---

## 11. Resuming on another machine

```bash
git clone git@github.com:Droidective/Droidective.git
cd Droidective
brew install xcodegen gitleaks prek shellcheck shfmt actionlint
prek install

# If #224/#225 are merged:
git checkout main && git pull

# If not yet merged:
git checkout feat/verification-harness

make verify          # expect: ADBKit 1167, AppTests 67
make verify-self     # expect: 6 guard tests pass
make test-mutation   # expect: killed 5, survived 0
make test-emulator   # needs a device or an AVD
make test-smoke      # needs an unlocked display
```

`make build` output lands at `DerivedData/Build/Products/Debug/Droidective.app`.
`pkill -x Droidective` before `open`-ing it — `open` re-activates a stale
instance otherwise.

### Files worth reading first

| path | why |
| --- | --- |
| `CLAUDE.md` | authoritative conventions; §"Bug-prevention gates" now describes the harness |
| `docs/cross-platform.md` | port strategy and phases, updated to reflect the landed core |
| `scripts/verify.sh` | the tiered gate |
| `ADBKit/Tests/ADBKitTests/PortabilityGuardTests.swift` | what "portable" is enforced to mean |
| `ADBKit/Tests/ADBKitTests/ProcessFixture.swift` | fixture format and redaction rules |

### Uncommitted work on the original machine

`App/Sources/Root/QuickActionsView.swift` carries a 7-line uncommitted edit
(a `.onChange(of: searchFocused)` that re-takes focus after a background
mouse-down). It is **not** in any commit or branch — it exists only in that
machine's working tree. Commit it or copy it across deliberately.

Also untracked and not committed: `.mcp.json`, `package.json`,
`package-lock.json` at the repo root.
