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

**Its own package** (`droidectived/`), like `ReactotronMCP` — not a target in
ADBKit's. ADBKit's graph has to stay free of swift-nio, because that leanness is
what lets `swift test` run on Windows; adding a NIO-dependent target back into
it would undo the MCP split. `DaemonCore` holds the logic so tests can reach it;
the executable is a thin `main`.

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

> **Status:** §§2–6 are implemented and tested (`droidectived/`, 70 tests),
> and `desktop/` is the first client driving them. Of §4's routes, `devices`,
> `features` and `actions` exist; file transfer and tool downloads (§8) do
> not. Of §5's topics, `devices` and `logcat` exist.

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

`/v1/features/list` carries what a client needs to *render* a feature, not
merely to name one: `keywords` (the vocabulary `FeatureDef.relevance` ranks
on — without it a palette can only match titles, and searching "battery" stops
finding the Simulate hub), `isAbsorbedByHub`, `isDestructive`, and per-field
`description`, `defaultValue`, `min`/`max`/`step` plus both halves of every
choice (`ar-EG` is not a label). `icon` stays out: SF Symbol names mean
nothing off Apple.

**Toggle actions take one implicit boolean named `on`.** It is a registry-wide
convention rather than a declared field — a `.toggleAction` has an empty
`fields` array — so a client has to know it. `FeatureEngine` reads
`params["on"]`, the Mac's `ToggleActionView` sends it, and
`aToggleActionIsDrivenByAnOnParameter` is what fails if it is ever renamed.

`/v1/apps/list` and `/v1/apps/control` are the same kind of pass-through, over
`AppsExplorerService` and `AppControlService`. The list response carries the
**verb table** alongside the apps (`actions: [{id, isDestructive}]`) rather
than leaving a client to keep its own copy: the two are always wanted
together, and a client with a private list of which verbs are dangerous will
eventually disagree with the runner about it. An unknown verb is a 400 that
never reaches the device. adb refusing — device gone, unauthorised — is a 502
carrying adb's own words, not a 500.

### 4.1 The filesystem routes

`/v1/files/list`, `/v1/files/op`, `/v1/files/info` and `/v1/files/pull` are the
first surface here that **writes** to a device, so the rules are worth stating.

```jsonc
// POST /v1/files/list   { "serial": …, "path": "/sdcard", "asRoot": false }
{ "path": "/sdcard",
  "entries": [ { "name": "DCIM", "isDir": true, "size": 4096,
                 "perms": "drwxrwx---" } ] }

// POST /v1/files/op     { "serial": …, "op": "copy", "path": "/sdcard/a",
//                         "destination": "/sdcard/b", "asRoot": false }
{ "ok": true, "message": "Copied" }
```

**Paths travel verbatim.** Device-shell quoting happens exactly once, in
ADBKit's `FileExplorerService`; a client that pre-escaped a path would have it
quoted a second time and address a different file. The daemon builds no shell
line of its own, and `FileExplorerServiceTests` asserts the quoted argument
vector for every verb, including the double quoting `su -c` needs.

**Every mutation is one route with the verb in the body**, the shape
`/v1/apps/control` already uses. `makeDirectory` and `delete` take `path`;
`copy` and `move` read it as the source and need a `destination` directory. An
unknown verb is a 400 (`unknown_operation`) and a copy with nowhere to land is
a 400 (`missing_destination`) — refused rather than guessed at, and neither
reaches the device. A device *refusing* a known verb is a 200 with `ok:false`,
the same split every other route keeps.

**`/v1/files/pull` writes to a host path the client chose.** Only the client
knows where its own Downloads folder is, so the daemon does not guess; it
writes exactly where it is told and answers with where that was. The Tauri
client picks `~/Downloads/Droidective/<name>` — the folder `export_text`
already uses — and checks the leaf name before joining it, because that name
came off a *device* listing.

`/v1/device/root` answers `RootService.detect`: `hasRootShell` (the only
definitive proof, and the File Explorer's Root-toggle gate) plus every signal
behind the verdict, so a client can say *why* rather than only *whether*.

### 4.2 The crash routes

`/v1/crashes/list` and `/v1/crashes/clear` are a pass-through over
`CrashExtractor`, which reads the crash buffer (falling back to the tail of
`main` when it is empty) and hands `CrashParser` the splitting. **Which buffer
to read and where one crash ends are not the daemon's questions** — ADBKit
answers them for both clients, and a client re-deriving either would eventually
disagree with the Mac about how many crashes a device has.

Each crash carries `kindLabel` beside `kind` for the same reason
`AppSummary.displayName` travels, and **both** renderings of the block: `raw`
as logcat printed it, `body` with the threadtime prefixes stripped. Deriving
one from the other means reimplementing that strip, and the Raw-log toggle
needs them both anyway.

Clearing is not the whole story and the wire cannot make it so: `logcat -c -b
crash` empties one buffer, and the same crashes can come back through the
main-buffer fallback on the next list. A client that offers Clear has to keep
its own high-water mark — the Mac does, and so does `desktop/`.

### 4.3 Errors

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
`iosLogs`. Each maps to an ADBKit `AsyncStream` that already exists. `pty`
(§5.2) came later and is the one that does not — it is a shell this process
starts, not a stream it forwards.

Three properties worth pinning now, because each one is a bug the Mac app
already had to solve:

- **Batched, not per-line.** `LogcatStreamer` already coalesces on a 300 ms
  flush (v3.6.1 moved it from 120 ms for exactly this reason). The socket sends
  whatever the flush produced; it must not re-split into one frame per line.
- **Backpressure is explicit — decided: drop oldest, mark the gap.** A slow UI
  must not grow an unbounded queue in the daemon (the trap that made us re-gate
  the macOS log readers). Each subscription gets a bounded buffer; on overflow
  the oldest go and the client receives `{"event":"dropped","count":N}` so the
  UI renders a visible gap rather than silently missing lines.

  This deliberately differs from the Mac app, which stalls: `bytes.lines` is
  pull-driven, so a slow consumer backpressures the pipe. Both are defensible
  and the divergence is intentional — a responsive UI with an honest gap beats
  one that silently falls behind real time. It also matches what the device
  already does: Android's logcat ring buffer drops under load regardless, so
  "lossless" was never actually on offer.
- **Unsubscribe tears down the child.** ADBKit already kills the adb child on
  task cancellation (`SystemProcessRunner.withTaskCancellationHandler`); the
  subscription must hold that task so closing the socket kills `adb logcat`
  rather than orphaning it.

### 5.1 Snapshot topics vs increment topics

`StreamProtocol.Topic.isSnapshot` splits the two, and a new topic has to answer
the question. A `logcat` batch is what just arrived and **appends**; a
`devices` batch is the whole current list and **replaces**.

For a snapshot topic the drop-oldest policy above is simply wrong, in two ways
that the first Tauri client hit immediately:

- **An empty batch is meaningful and must be sent.** `items: []` is the only
  way to say "nothing is connected". Skipping it — which the buffered path did,
  since it had nothing to enqueue — left a UI showing a device that had already
  been unplugged, and made a first subscribe with nothing attached
  indistinguishable from one still loading. Fixed: a snapshot is delivered even
  when empty.
- **An unsent snapshot is replaced, not queued.** An older device list is
  worthless once a newer one exists, so a snapshot topic can never emit
  `dropped`. Handing a client stale state plus a "you missed 16 device lists"
  marker would be worse than useless: there is nothing to do with the gap.

### 5.2 The `pty` topic — the socket goes both ways

The Terminal needed the first topic a client can *send into*, so `Operation`
grew `write` and `resize` beside `subscribe`/`unsubscribe`. Both act on a
subscription that already exists and are answered only when they are refused —
a terminal that acknowledged every keypress would spend most of a paste talking
about itself.

```jsonc
// client → server: open a shell. Host-scoped, so no serial is required.
{ "op": "subscribe", "id": 3, "topic": "pty",
  "params": { "serial": "R58M", "columns": 120, "rows": 40 } }
// server → client: whatever the shell wrote, base64
{ "id": 3, "event": "batch", "items": [ { "data": "aGVsbG8NCg==" } ] }
// client → server: keystrokes (base64) and the window
{ "op": "write",  "id": 3, "params": { "data": "bHMK" } }
{ "op": "resize", "id": 3, "params": { "columns": 100, "rows": 30 } }
// server → client: the shell exited
{ "id": 3, "event": "ended", "reason": "process_exited" }
```

Four decisions, each of which is a bug if taken the other way:

- **Base64 both directions, because this is the one payload that is bytes.** A
  pty read ends wherever its buffer filled, so a chunk can stop mid-character;
  a JSON string would replace the half with U+FFFD and only on non-ASCII, which
  is how that ships. The same reasoning runs inbound: terminal input includes
  the control codes a JSON string cannot carry — Ctrl-C is `0x03`, and it is the
  single most important key a terminal has to deliver.
- **Host-scoped, not device-scoped.** A shell runs on the machine; `serial` only
  exports `ANDROID_SERIAL` into it, so adb inside needs no `-s` — the way the
  Mac scopes a terminal tab. `needsSerial` is false because a terminal must open
  with nothing connected, which is when one is most wanted.
- **`process_exited` is its own end reason.** Typing `exit` is how a terminal is
  meant to end, and calling it `device_disconnected` would have the pane render
  a fault. A failed `exec` arrives the same way, because it reaches the parent as
  the terminal hanging up rather than as an error.
- **Input against the wrong subscription is refused, not discarded.** Unlike
  `unsubscribe`, which is lenient so a client racing its own teardown sees no
  spurious failure, a `write` to an unknown id or to a topic that only observes
  answers `failed`. A write that lands nowhere presents as a terminal ignoring
  the keyboard, which is a bug worth hours; the narrow race — a keystroke just
  after the shell exited — is one the client already knows about from `ended`.

The shell itself is `Pty` over a small `CPty` C target: `fork` plus
`ioctl(TIOCSCTTY)` is the only way a child acquires a controlling terminal, and
Swift marks `fork` unavailable because only async-signal-safe calls are legal
between it and `exec`. Windows has no pty here — ConPTY is a different API
rather than a variation — so `openPty` throws and the client renders the reason.

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

## 8. Decisions and open questions

**Decided — drop policy:** drop oldest with a gap marker. See §5.

**Decided — macOS stays native, indefinitely.** The Mac app keeps linking
ADBKit directly and never talks to the daemon. That is two integration paths to
maintain, accepted knowingly: the shipping Mac flow is the thing with users on
it, and no daemon work should ever be able to reach it. Practically this means
the daemon is free to make choices the Mac app does not share (the drop policy
above being the first), and nothing here should be designed as a migration
path.

Still open:

1. **File transfer.** `adb push`/`pull` over HTTP needs streaming bodies and
   progress; probably its own endpoint pair rather than the JSON action path.
3. **Tool downloads.** `ManagedToolStore` fetches from GitHub. Does the daemon
   own that, or the UI? Daemon, most likely — it already has the digest
   verification — but it means the daemon needs outbound network, which
   complicates the "loopback only" story.
