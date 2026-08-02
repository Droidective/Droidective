# Cross-platform: Windows & Linux

The port strategy, what is already true on `main`, and what comes next.

## Shape

Three layers; the top one is per-platform, everything under it is shared Swift:

1. **ADBKit** (the existing core) — compiles and tests on macOS, Linux and
   Windows. All adb logic, parsers, and services live here.
2. **`droidectived`** (phase 2, landed) — a small local daemon target
   exposing ADBKit over localhost HTTP + WebSocket JSON so a non-Swift UI can
   drive it. It doubles as the remote-host protocol an iOS companion would
   need someday.
3. **UI** — macOS keeps the native SwiftUI app unchanged. Windows/Linux get
   one shared web UI (React, the same stack as `website/`) wrapped in Tauri,
   shipping `droidectived` as a sidecar process.

Why this split: measured on this codebase, the logic layer is ~94% portable
(10 of 112 files touched Apple-only frameworks) while the SwiftUI layer is 0%
portable — and off-Apple Swift GUI toolkits are alpha-grade while the web
stack is mature. Rewriting the core in another language would throw away the
900+-test suite.

## Phase 1 (landed): a portable core

`cd ADBKit && swift test` passes on Linux — CI runs the same suite in a
`swift:6.2` container (`test-linux`) — and on Windows, where `build-windows`
now runs it rather than only compiling it. All three hosts run the same
suite.

Apple-only subsystems are compile-gated with `#if canImport(...)`, not
stubbed — a platform that can't mirror simply doesn't expose the type:

| Subsystem | Off-Darwin state |
| --- | --- |
| Mirror pipeline (`MirrorSession`, transport, H.264 decode, recorder, audio) | absent — other hosts drive the scrcpy desktop app (scrcpy ships Windows/Linux builds) |
| `ScreenRecorder` (rides the mirror) | absent — record via scrcpy `--record` later |
| `ReactotronServer` / `ReactotronService` (Network.framework WebSocket listener) | absent — needs a portable listener; the protocol layer next door is already pure Swift |
| `ConsoleLinkDetector` | returns no spans (corelibs has no `NSDataDetector`); a web UI linkifies in its own view layer |
| `ProcessStats` (the watchdog's `proc_pid_rusage` sampling) | returns nil |
| `HostNetwork.primaryIPv4` | `getifaddrs` on Linux; nil on Windows (GetAdaptersAddresses is a follow-up) |
| `URLSessionTransport`'s TLS opt-out (API client) | compiles and runs, but `validateTLS: false` cannot be honoured — corelibs has no server-trust protection space — so its two delegate suites are Apple-scoped |

Portable seams that changed shape:

- `FileHandleLines` supplies the logcat and simulator-log streams *off-Darwin*,
  where `FileHandle.bytes.lines` does not exist: CRLF-tolerant, tested, and
  backed by a dedicated blocking-read thread because corelibs never delivers
  `readabilityHandler`'s empty EOF callback when the final data and the
  writer's close arrive together. **Apple platforms deliberately keep
  Foundation's own `bytes.lines`.** It is pull-driven, so a slow consumer
  backpressures the pipe rather than queueing lines in an unbounded
  `AsyncStream` buffer — and this is the live logcat feed, the most-used
  surface in the shipping app. The rule the port follows: gate, don't replace;
  a portability edit must leave the macOS path byte-identical.
- SHA-256 digests come from CryptoKit on Apple platforms and swift-crypto's
  API-compatible `Crypto` elsewhere — the package's first dependency, linked
  only off-Apple.
- `HostArchive` picks extraction commands per host: `/usr/bin/unzip` and
  `/usr/bin/tar` on POSIX, `System32\tar.exe` (bsdtar — reads zips too) on
  Windows. frida's bare `.xz` decompresses via Compression on macOS and the
  `xz` CLI on Linux; unsupported on Windows for now.
- `ToolLocator` knows per-OS SDK roots (`~/Library/Android/sdk`,
  `~/Android/Sdk`, `%LOCALAPPDATA%/Android/Sdk`), `.exe` names, and per-OS
  fallbacks: macOS keeps the zsh login-shell trick, Linux honors `$SHELL`,
  Windows scans the registry-provided PATH directly.
- `EmulatorService.spawnDetached`: Darwin keeps `POSIX_SPAWN_SETSID`; Linux
  gets the same session-detach via `setsid --fork`; Windows children are
  already independent of the parent's lifetime.
- Every URLSession user imports FoundationNetworking off-Darwin. The JS
  console client (`URLSessionWebSocketTask`) compiles on Linux; its wire
  tests still fake the CDP server with `NWListener`, so they run Apple-only
  until that fake gets a portable listener.

What a Linux host genuinely runs today: device monitoring, every adb
instant/form/toggle action, logcat streaming, file explorer, app management,
crash catcher, overrides, custom commands, and managed tool downloads —
everything the mock-driven suite exercises.

Run the Linux suite locally with `make test-linux` (Apple's `container` CLI;
`container system start` once per boot, and it needs a kernel installed via
`container system kernel set --recommended`). CI's `test-linux` job is the
authoritative gate — it needs no local runtime.

The rule is enforced rather than remembered: `PortabilityGuardTests` scans
ADBKit for Apple-only imports and the corelibs traps listed above and fails on
any that is not inside a matching `#if canImport(...)` gate. Its allowlist is
empty, and a companion test fails on a stale entry, so debt cannot be excused
and then quietly forgotten.

## Phase 2 (landed): `droidectived`

**Full protocol design and current state: `droidectived-protocol.md`.** Shape:

- An executable target in ADBKit's package; `swift build` produces it on
  Linux/Windows (static-musl is an option on Linux).
- Transport: localhost-bound HTTP for request/response (list devices, run an
  action, list apps…) plus a WebSocket for streams (device changes, logcat,
  performance samples). JSON bodies mirror ADBKit's `Sendable` models.
- Auth: a random token written 0600 under the app-support dir; the UI reads
  it and sends it as a header. Nothing listens beyond loopback by default.
- Lifecycle: the Tauri app spawns the daemon as a sidecar and owns its
  lifetime; `--port 0` plus a printed port line avoids collisions.

## Phase 3 (started): the Windows/Linux app

`desktop/` — Tauri 2 + React 19 + Vite + Tailwind v4 over `droidectived`; see
`desktop/README.md`. Working today: the device picker, the action palette
(search, forms, toggles, destructive confirmation) and live logcat with
visible gap markers. Still to come: the full-screen view features, apps and
files, then the terminal via xterm.js against a daemon PTY endpoint.
Mirroring stays with the scrcpy desktop app.

Two decisions worth keeping:

- **The webview never talks to the daemon; Rust does.** The daemon refuses a
  request whose `Origin` is not loopback and sends no CORS headers, so a
  webview origin (`tauri://localhost`, `http://tauri.localhost`) gets a 403.
  That is the rebinding guard working as designed, not something to route
  around — so every call goes through a Tauri command, the bearer token never
  leaves the Rust process, and `capabilities/default.json` grants the webview
  no shell, filesystem or HTTP permission of its own.
- **Hub members are listed standalone.** The Mac catalog hides the features a
  hub screen absorbs, because the hub is how you reach them. This app has no
  hub screens yet and 13 of its 20 runnable actions are absorbed, so hiding
  them would remove most of the app.

The daemon ships as a **sidecar**: `scripts/build-daemon-sidecar.sh` builds it
with `swift build` and names it for the host triple, which is what Tauri's
`externalBin` resolves. Tauri checks for it at *build* time, so a missing
daemon fails the Rust build rather than the app.

Building the UI turned up two gaps in the phase-2 wire contract, both now
fixed and tested: the feature summary was missing everything a form or a
search needs (`keywords`, field bounds, choice labels — protocol doc §4), and
the `devices` topic silently swallowed an empty device list, so an unplugged
device never disappeared (§5.1).

`make desktop-test` is the gate; CI runs it as `desktop-web` (typecheck,
oxlint, vitest, a production frontend build) and `desktop-native` (the Swift
sidecar, then `cargo fmt`/`clippy`/`test` on Linux).

## Follow-ups

- [x] `droidectived` scaffold — own package, loopback bind on port 0 with the
      printed port line, token auth with the Host/Origin checks, and
      `POST /v1/devices/list`, proven over a real socket (24 tests)
- [ ] Portable WebSocket client for tests, so the stream socket's own suite
      runs off-Darwin. corelibs-Foundation has no `URLSessionWebSocketTask`
      ("WebSockets not supported by libcurl"), so those four tests are
      Apple-scoped today. The *server* is portable NIO and runs everywhere —
      only the harness is missing. The raw-socket probe that caught the frame
      masking bug is the obvious basis for one.
- [x] `droidectived` streams: the WebSocket, the topic subscriptions, and the
      drop-oldest buffer with its gap marker
- [ ] Portable fake CDP server so the JSConsoleClient wire tests run on Linux
- [ ] Reactotron listener off Network.framework (SwiftNIO or raw sockets)
- [x] Windows: the last 3 tests, and `build-windows` flipped to `swift test`.
      Both causes turned out to be different from the standing hypotheses, and
      both were found by running the suite there and reading the output rather
      than reasoning about it:
      (1) `capturesStderrAndNonZeroExit` was not a launch failure — the child
      ran and its stderr arrived intact. `SystemProcessRunner` nils the exit
      code unless `terminationReason == .exit`, and corelibs reports a
      non-`.exit` reason on Windows for an ordinary non-zero exit as readily as
      for a TerminateProcess kill. Since Windows has no signals, the reason
      cannot separate the two; the runner now trusts the flags it already sets
      before killing a child. Gated, so POSIX is untouched.
      (2)+(3) The APK suites' seeded tools never resolved, because
      `isExecutableFile` on Windows asks what kind of binary a file is and a
      shell script named `aapt2.exe` is not one. The fixtures now copy a real
      system binary there, which keeps the production predicate under test.
- [ ] Windows: xz decode for frida assets; `HostNetwork` via GetAdaptersAddresses
- [ ] Linux: interface ranking in `HostNetwork.pickPrimary` (en*/eth*/wl* over docker0/veth)
- [ ] API client: portable expectations for `URLSessionTransport` so
      `ApiTransportTests` / `ApiTransportLiveTests` run off-Darwin
- [ ] A guard for corelibs-*unavailable* / *deprecated* Foundation symbols.
      `PortabilityGuardTests` only catches Apple-only imports and a listed set
      of traps, so it missed both API-client breaks
      (`NSURLAuthenticationMethodServerTrust`,
      `NSURLErrorFailingURLStringErrorKey`); only the real Linux compile found
      them. Until that exists, `test-linux` is the only thing standing between
      a new macOS feature and a broken port.
