# Cross-platform: Windows & Linux

The port strategy, what is already true on `main`, and what comes next.

## Shape

Three layers; the top one is per-platform, everything under it is shared Swift:

1. **ADBKit** (the existing core) — compiles and tests on macOS and Linux, and
   build-verifies on Windows. All adb logic, parsers, and services live here.
2. **`droidectived`** (phase 2, not yet built) — a small local daemon target
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
`swift:6.2` container (`test-linux`) — and Windows compiles the library and
test target (`build-windows`; running the tests there waits on a Windows audit
of the process-spawning tests, which hardcode POSIX paths).

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

Portable seams that changed shape:

- `FileHandleLines` replaces Darwin-only `FileHandle.bytes.lines` for the
  logcat and simulator-log streams: `readabilityHandler`-based (the same
  non-blocking pattern as `SystemProcessRunner`), CRLF-tolerant, tested.
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

## Phase 2: `droidectived`

Sketch — details land with the implementation:

- An executable target in ADBKit's package; `swift build` produces it on
  Linux/Windows (static-musl is an option on Linux).
- Transport: localhost-bound HTTP for request/response (list devices, run an
  action, list apps…) plus a WebSocket for streams (device changes, logcat,
  performance samples). JSON bodies mirror ADBKit's `Sendable` models.
- Auth: a random token written 0600 under the app-support dir; the UI reads
  it and sends it as a header. Nothing listens beyond loopback by default.
- Lifecycle: the Tauri app spawns the daemon as a sidecar and owns its
  lifetime; `--port 0` plus a printed port line avoids collisions.

## Phase 3: the Windows/Linux app

Tauri 2 + React, starting with the palette, actions, logcat, apps, and files;
the terminal later via xterm.js against a daemon PTY endpoint; mirroring
stays with the scrcpy desktop app.

## Follow-ups

- [ ] `droidectived` scaffold + protocol tests
- [ ] Portable fake CDP server so the JSConsoleClient wire tests run on Linux
- [ ] Reactotron listener off Network.framework (SwiftNIO or raw sockets)
- [ ] Windows: audit the process-spawning tests so `swift test` runs in CI
- [ ] Windows: xz decode for frida assets; `HostNetwork` via GetAdaptersAddresses
- [ ] Linux: interface ranking in `HostNetwork.pickPrimary` (en*/eth*/wl* over docker0/veth)
