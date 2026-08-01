# `droidectived` — protocol design

Phase 2 of the port (see `cross-platform.md`). A local daemon exposing ADBKit
over loopback so a non-Swift UI can drive it. **This is a design for review —
nothing here is implemented yet.**

The point of writing it first: the transport shape, the error contract, and the
stream lifecycle are all cheap to argue about on paper and expensive to change
once a Tauri UI depends on them.

---

## 1. What it is for, and what it is not

The Windows/Linux app cannot be SwiftUI, and rewriting ADBKit in another
language would discard ~1,550 tests. So the UI talks to the logic over a local
socket instead of linking it.

| | |
| --- | --- |
| **In scope** | device list + changes, every registry action, logcat, app management, files, crashes, performance |
| **Out of scope (phase 2)** | mirroring (the desktop scrcpy app handles it off-Apple), the terminal (needs a PTY endpoint — phase 3), MCP (Apple-only package) |
| **Not a remote-control server** | loopback only, token-gated. An iOS companion could reuse the protocol later, but that is not a phase-2 goal and nothing here should assume a trusted network. |

**macOS keeps its native app and does not use the daemon.** That matters: it
means the daemon can be developed and shipped without any risk to the flow
people use today. It also means the daemon is *not* exercised by the Mac app, so
it needs its own tests rather than riding on the existing suite.

## 2. Shape

An `executableTarget` in ADBKit's package. That package now has one dependency
(`swift-crypto`, off-Apple only), so the daemon builds on all three hosts from a
lean graph — the reason the MCP split mattered.

```
Tauri app  ──spawns──▶  droidectived --port 0 --token-file <path>
     │                        │
     └── HTTP + WebSocket ────┘   (127.0.0.1 only)
```

The daemon is a **sidecar owned by the UI**, not a system service: no
auto-start, no daemonisation, no install step. The UI spawns it, reads the port
it prints, and kills it on quit. A stale daemon outliving its UI is the failure
mode to design out, not a feature.

## 3. Transport

**Request/response over HTTP; streams over one WebSocket.**

Rejected alternatives, briefly, since this is the decision most expensive to
revisit:

- *WebSocket for everything* — every request needs hand-rolled correlation ids
  and timeouts, which is HTTP re-implemented badly.
- *gRPC* — a code-generation toolchain and a heavier Swift dependency, for a
  loopback link where JSON costs nothing measurable.
- *HTTP long-poll for streams* — logcat can emit thousands of lines a second;
  polling either drops lines or burns CPU.
- *Unix domain socket instead of TCP* — better on POSIX, but NIO's Windows UDS
  support is one of the genuinely unsupported channels. Loopback TCP works
  everywhere, which is the whole point.

### 3.1 Binding and port

Bind `127.0.0.1:0`, then print exactly one line to stdout and flush:

```
droidectived listening 127.0.0.1:54123
```

Port 0 avoids collisions with anything already running, including a second
Droidective. The UI parses that line; if it does not arrive within a timeout,
the daemon is broken and the UI says so rather than hanging.

### 3.2 Auth

A 32-byte random token, hex-encoded, written `0600` to a path the UI passes in
(`--token-file`). Every request carries `Authorization: Bearer <token>`.

Loopback binding alone is **not** sufficient: any local process, including a
browser tab via DNS rebinding, can reach `127.0.0.1`. So, mirroring what
`McpHTTPListener` already does for MCP:

- reject any request whose `Origin` is present and not loopback,
- reject `Host` headers that are not `127.0.0.1:<port>` or `localhost:<port>`,
- constant-time token comparison,
- no CORS headers — nothing browser-based should be talking to this.

Token in a file rather than argv, because argv is world-readable via `ps` — the
same reasoning `ApkSigningService` already uses for keystore passwords.

## 4. Request/response

`POST /v1/<area>/<verb>`, JSON in, JSON out. Bodies mirror ADBKit's `Sendable`
models so the encoder is `JSONEncoder` over existing types, not a parallel
hierarchy that can drift.

```jsonc
// POST /v1/devices/list  → 200
{ "devices": [ { "serial": "emulator-5554", "state": "device",
                 "platform": "android", "model": "sdk_gphone64_arm64" } ] }
```

```jsonc
// POST /v1/actions/run
{ "featureId": "dark-mode", "serial": "emulator-5554",
  "fields": { "enabled": "true" } }
// → 200
{ "ok": true, "message": "Dark mode on", "command": "adb -s … shell cmd uimode night yes" }
```

Actions route through `FeatureEngine.dispatch`, so **the daemon adds no
feature knowledge**. A new registry action is reachable over HTTP the day it
lands, with no daemon change — the same property `implementedIDs` already
gives the Mac app. An unknown `featureId` is a 404, not a 500.

### 4.1 Errors

One shape everywhere, so the UI has one error path:

```jsonc
{ "error": { "code": "device_not_found",
             "message": "emulator-5554 is not connected",
             "detail": "adb: device 'emulator-5554' not found" } }
```

`code` is a stable machine string; `message` is user-facing; `detail` is raw
tool output when there is any. HTTP status carries the class (400 malformed,
401 bad token, 404 unknown feature/device, 409 wrong device state, 500 daemon
bug, 502 adb itself failed).

**A non-zero adb exit is not a transport error.** `AdbClient` already models
this — it returns a structured `AdbResult` and only throws on `.adbNotFound` —
and the HTTP layer must preserve that distinction rather than flattening every
failure into a 500.

## 5. Streams

One WebSocket at `/v1/stream`, multiplexed by subscription, rather than a
socket per stream: a UI showing logcat plus device changes plus performance
would otherwise hold three sockets with three lifecycles.

```jsonc
// client → server
{ "op": "subscribe", "id": 7, "topic": "logcat",
  "params": { "serial": "emulator-5554", "filter": "E" } }
// server → client
{ "id": 7, "event": "batch", "items": [ /* LogLine */ ] }
{ "id": 7, "event": "ended", "reason": "device_disconnected" }
// client → server
{ "op": "unsubscribe", "id": 7 }
```

Topics for phase 2: `devices`, `logcat`, `performance`, `networkSpeed`,
`iosLogs`. Each maps to an ADBKit `AsyncStream` that already exists.

Three properties worth pinning now, because each one is a bug the Mac app
already had to solve:

- **Batched, not per-line.** `LogcatStreamer` already coalesces on a 300 ms
  flush (v3.6.1 moved it from 120 ms for exactly this reason). The socket sends
  whatever the flush produced; it must not re-split into one frame per line.
- **Backpressure is explicit.** A slow UI must not grow an unbounded queue in
  the daemon — the same trap that made me re-gate the macOS log readers. Each
  subscription gets a bounded buffer and drops oldest with a
  `{"event":"dropped","count":N}` marker, so the UI can show a gap instead of
  the daemon eating memory. **This is the part I would most want reviewed.**
- **Unsubscribe tears down the child.** ADBKit already kills the adb child on
  task cancellation (`SystemProcessRunner.withTaskCancellationHandler`); the
  subscription must hold that task so closing the socket kills `adb logcat`
  rather than orphaning it.

## 6. Lifecycle

- **Startup:** parse args, write the token, bind, print the port line.
- **Shutdown:** on `SIGTERM`/`SIGINT`, stop accepting, cancel every
  subscription, wait briefly for children, exit 0.
- **Orphan protection:** `--parent-pid <pid>`; the daemon polls and exits when
  the parent disappears. Without it, a crashed UI leaves a daemon holding adb
  children — the failure people notice as "adb is stuck".
- **Single instance is *not* enforced.** Port 0 makes concurrent daemons
  harmless, and enforcing uniqueness needs a lockfile whose staleness is its own
  bug.

## 7. Testing

The daemon must not be the one part of the system verified by hand.

- **Protocol tests** over a real loopback socket with a `MockProcessRunner`
  behind ADBKit — the `McpHTTPListenerTests` pattern, which already proves this
  works in this codebase.
- **A golden contract test.** `McpGoldenContractTests` pins the MCP tool
  signatures so a change to the wire surface has to be a visible diff in the
  PR. The daemon's route table deserves the same, or the Tauri UI will break on
  a rename nobody noticed.
- **A route-completeness invariant** in the registry-invariant style: every
  `FeatureEngine.implementedIDs` entry must be reachable over HTTP, so a new
  action cannot be silently unreachable from the web UI. This is the daemon's
  version of `everyImplementedActionResolvesToARunner`.
- Tests run on all three hosts — the daemon is the first component whose
  *runtime* behaviour matters off-Apple, so `test-linux` and the Windows job
  become load-bearing rather than compile checks.

## 8. Open questions

1. **Drop policy.** Drop-oldest with a gap marker, or apply backpressure and let
   the daemon's read of adb stall? Dropping favours a responsive UI; stalling
   favours completeness. The Mac app implicitly chose stalling (pull-driven
   reads); the daemon probably wants dropping, and the two differing is
   defensible but should be deliberate.
2. **Does the Mac app ever adopt this?** Keeping it daemon-free is zero-risk but
   means two integration paths forever. My inclination is to leave macOS alone
   until the daemon has shipped on another OS and proven itself.
3. **File transfer.** `adb push`/`pull` over HTTP needs streaming bodies and
   progress; probably its own endpoint pair rather than the JSON action path.
4. **Tool downloads.** `ManagedToolStore` fetches from GitHub. Does the daemon
   own that, or the UI? Daemon, most likely — it already has the digest
   verification — but it means the daemon needs outbound network, which
   complicates the "loopback only" story.
