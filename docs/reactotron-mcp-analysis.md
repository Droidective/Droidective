# Reactotron MCP support — implementation analysis

*Analysis date: 2026-07-20. Sources: Droidective `main` @ a49fca9; `infinitered/reactotron`
master @ 763c1c8 (2026-05-28); npm `reactotron-mcp` 0.3.0 (published 2026-03-25);
`modelcontextprotocol/swift-sdk` 0.12.1 (2026-04-29). All upstream claims below were read
from cloned source, not docs.*

## 1. Executive summary

Reactotron shipped first-party MCP support in two forms. Droidective should mirror the
newer, embedded form: an **opt-in Streamable HTTP MCP server bound to `127.0.0.1:4567/mcp`**
running inside the app, reading a dedicated ring buffer fed by our existing
`ReactotronServer` WebSocket relay, exposing Reactotron's exact 10-tool + 8-resource
contract (plus a default-on redaction layer), built on the official
`modelcontextprotocol/swift-sdk` `Server` + `StatefulHTTPServerTransport`.

Users then connect any MCP client with the same one-liner Reactotron documents:

```bash
claude mcp add --transport http reactotron http://localhost:4567/mcp
```

Nothing changes on the wire to the RN app (WebSocket 9090, same protocol), nothing changes
in the existing Reactotron UI, and the MCP layer is a separate ADBKit-package target that
can fail, stop, or be disabled without touching the relay.

**The one decision needing user sign-off:** the HTTP listener. Reliability favors adding
`swift-nio` and porting the SDK's own tested reference listener (§6.3); the repo's
no-new-dependencies policy favors a hand-rolled `NWListener` HTTP server. Everything else
in this document is unchanged either way.

## 2. Ground truth: what upstream actually built

Two distinct first-party implementations exist. They have different transports, different
tool names, and different architectures. Chronology matters:

### 2.1 npm `reactotron-mcp` 0.3.0 (standalone proxy — March 2026)

A stdio MCP server run via `npx -y reactotron-mcp`. It interposes a **WebSocket proxy on
port 9091** between the RN app and the desktop app: the RN app must be reconfigured
(`Reactotron.configure({ port: 9091 })`), the proxy forwards to 9090 and captures
everything. 16 `get_*`-style tools, 11 resources, 5 MCP prompts (`debug_app`,
`trace_action`, `diagnose_network`, `debug_performance`, `debug_errors`). Env config:
`REACTOTRON_PROXY_PORT=9091`, `REACTOTRON_PORT=9090`, `REACTOTRON_TIMEOUT=5000`.

Notable: **this works against Droidective today with zero changes on our side** — the
proxy forwards to whatever serves 9090, which is us. It's a fallback story, not the
feature: it requires an RN-side port change, an extra Node process, and its capture buffer
lives in the proxy, duplicating what Droidective already holds.

### 2.2 Embedded `lib/reactotron-mcp` (in the desktop app — May 2026, master)

The newer direction, shipped inside `reactotron-app` 3.11.0 and the design to mirror:

- **Transport**: Streamable HTTP via `@modelcontextprotocol/sdk` (^1.27.0). Raw Node
  `http.createServer` bound to **`127.0.0.1` only, default port 4567**, single route
  `POST /mcp` (405 on GET, 404 elsewhere, 204 on OPTIONS preflight).
- **Stateless**: a fresh `McpServer` + `StreamableHTTPServerTransport(sessionIdGenerator:
  undefined)` per request, closed when the response closes. No session persistence.
- **Off by default** — toggled from the app's footer "MCP" button; settings in a modal;
  config persisted.
- **Data source**: subscribes to the relay's `command` event and keeps its own in-memory
  ring buffer, **`BUFFER_SIZE = 500`** commands, oldest dropped. That buffer is the entire
  query surface — independent of the desktop timeline (`clear_timeline` clears only the
  MCP buffer).
- **Request/response tools** (e.g. `request_state`) send a command over the relay and
  **poll the buffer** for the matching response type + clientId — 100 ms tick, **1500 ms
  timeout**.
- **Output caps**: every result compact-serialized then truncated at
  **`MAX_RESPONSE_CHARS = 800_000`** with an inline `[TRUNCATED …]` suffix that tells the
  LLM how to narrow (pass a `path`, use `timeline/{type}`, `clear_timeline`). Payload
  previews 200 chars, network body previews 500 chars.
- **Multi-app**: `resolveClientId` errors "No apps connected" at 0 and "Multiple apps
  connected. Specify clientId. Available: …" at >1 with none given; auto-selects a sole app.
- **Redaction** (§7): default-on, applied only at the MCP boundary.

**Tools (exactly 10, verified in `src/tools.ts`):** `dispatch_action`, `request_state`,
`request_state_keys`, `swap_state`, `send_custom_command`, `list_custom_commands`,
`show_overlay`, `clear_timeline`, `subscribe_state`, `unsubscribe_state`.

**Resources (8, `src/resources.ts`):** `reactotron://timeline` (newest-first summaries,
payloads stripped to 200-char previews), `reactotron://timeline/{type}` (ResourceTemplate
with completion over types seen in the buffer; full payloads),
`reactotron://state/current` (latest cached `state.values.response`),
`reactotron://network/log` (api.response summaries), `reactotron://apps`,
`reactotron://benchmarks`, `reactotron://state/subscriptions`, `reactotron://asyncstorage`.
All return `application/json` with a `_meta` connection block
(`no_apps_connected`/`single_app`/`multiple_apps` + a hint).

### 2.3 Wire protocol facts that matter for the MCP layer

From `reactotron-core-server` 3.3.0 / `reactotron-core-contract` 0.4.0 (authoritative
`Command` envelope: `{type, connectionId, clientId?, date, deltaTime, important,
messageId (server-assigned monotonic), payload}`):

- There is **no request/response correlation id** in the protocol. Correlation is by
  (command type, clientId, arrival-after-send) — inherently racy; upstream accepts it.
- `custom` and `setClientId` are string-literal types outside the `CommandType` enum.
- `client.intro` carries an optional **`mcpRedaction`** field (`McpRedactionConfig`)
  — the per-app redaction handshake (§7). ADBKit's parser currently ignores unknown intro
  fields leniently, so reading it is additive.
- Droidective's `ReactotronServer` already mirrors the handshake (clientId assignment,
  stale-twin drop, `state.values.subscribe` replay) and the full command-type set —
  ADBKit's `ReactotronCommandType` covers every type in the upstream enum.

## 3. Ground truth: what Droidective already has

Inventory from `ADBKit/Sources/ADBKit/Services/Reactotron/` and
`App/Sources/FeatureDetail/Views/ReactotronView.swift`:

| Layer | Type | Notes |
|---|---|---|
| Relay server | `actor ReactotronServer` | NWListener + NWProtocolWebSocket, port 9090, loopback-or-LAN scope, 30 s ping, 64 MiB max frame, per-connection FIFO frame feeds, multi-client with stale-twin dedup — the same job as `reactotron-core-server` |
| Orchestrator | `actor ReactotronService` | owns the server, runs `adb reverse tcp:9090` (3× retry), forwards `send`/`broadcast` |
| Protocol | `ReactotronCommand` / `ReactotronEvent` / `JSONValue` | lenient Codable decode, sentinel repair, pure `ReactotronEvent(command:)` parser — all Sendable |
| Retention math | `enum ReactotronTimeline` | pure drop-count budgeting (2000 items / 128 MiB, hysteresis) |
| Retention store | `@MainActor @Observable ReactotronSession` (App layer) | **the timeline items live on the MainActor UI session** — the one structural gap for MCP |
| Outbound commands | `ReactotronSession` → `service.send/broadcast` | dispatch action, state request/keys/backup/restore, subscribe, custom command, REPL — the exact surface upstream's tools drive |
| Tests | `ReactotronServerTests` (real loopback WS client), `ReactotronProtocolTests` (~35), `ReactotronTimelineTests`, `ReactotronCurlTests` | the server test file is the template for MCP socket tests |

No MCP or JSON-RPC code exists anywhere in the repo. Relevant known bug (backlog): a
`client.intro` frame draining after `dropConnection` can resurrect a ghost client in the
UI's client list — must be fixed before MCP reads client state (§8, P0).

Key architectural consequence: **`ReactotronServer.start()` returns a single-consumer
`AsyncStream`**, currently consumed by the UI session. MCP needs a second consumer, so the
service layer gains event fan-out (§6.4). Upstream's design (a separate MCP buffer, UI
untouched) fits us perfectly: no refactor of the 3,000-line `ReactotronView`.

## 4. Goals and non-goals

**Goals**

1. An AI agent (Claude Code, Cursor) can read the live Reactotron timeline — logs, network
   requests, Redux/MST state, benchmarks — and drive the app (dispatch actions, custom
   commands) while Droidective runs. No RN-app changes beyond what Reactotron itself needs.
2. Contract parity with upstream's embedded server: same URL shape, same 10 tools, same 8
   resources, same redaction semantics — so upstream docs, prompts, and user muscle memory
   transfer.
3. Reliability as the top requirement: bounded memory, no polling loops, no unbounded
   sessions, isolated failure domains, and the whole logic layer testable in `swift test`
   without a device or a socket.

**Non-goals (v1)**

- The stdio-proxy mode (npm 0.3.0 covers that user today).
- MCP resource *subscriptions* (`notifications/resources/updated`) — client support is
  weak (Cursor ignores resources; Claude Code doesn't drive loops off pushes). Tools are
  the load-bearing surface; resources ship because they're nearly free off the same buffer.
- Exposing non-Reactotron Droidective data (logcat, device info) over MCP. Tempting, out
  of scope here; the module layout deliberately leaves room for it.
- LAN-reachable MCP. Loopback only, always (the WS relay's LAN toggle is unrelated).

## 5. Architecture

```
RN app ──ws://localhost:9090──▶ ReactotronServer (actor, existing)
                                      │ AsyncStream<Event>
                                ReactotronService (actor, existing)
                                      │ NEW: event fan-out (N subscribers)
              ┌───────────────────────┴───────────────────────┐
   ReactotronSession (@MainActor, UI — unchanged)     McpCommandStore (actor, NEW)
                                                       ring buffer ≤500 cmds + byte cap
                                                       clients / state cache / custom cmds
                                                       awaitCommand() correlation
                                                              │
                                                     McpToolHandlers + McpResources (NEW)
                                                       redaction → summarize → truncate
                                                              │
                                            MCP.Server (per session, official swift-sdk)
                                                              │
                                            StatefulHTTPServerTransport (swift-sdk)
                                                              │
                                            McpHTTPListener (NEW) 127.0.0.1:4567 /mcp
                                                              │
                                            Claude Code / Cursor (Streamable HTTP)
```

Failure isolation: the MCP stack (store → listener) is downstream of the relay and can
crash, stop, or be toggled off without affecting the WS server or the UI. The relay never
awaits the MCP layer.

## 6. Design decisions

### D1 — Embedded Streamable HTTP server; no stdio shim. *(decided)*

MCP clients normally spawn a stdio child, but our server lives in a running GUI app. The
two proven Mac-app patterns: Figma Dev Mode runs a localhost HTTP MCP endpoint in the app
(`127.0.0.1:3845/mcp`); Xcode 26 ships an `mcpbridge` stdio shim over XPC. Upstream
Reactotron chose embedded HTTP. Claude Code (`--transport http`) and Cursor
(`"type": "http"` in `.mcp.json`) both speak Streamable HTTP natively, so a shim buys
nothing today. Revisit only if a target client without HTTP support appears.

### D2 — Official `modelcontextprotocol/swift-sdk`, pinned. *(decided)*

v0.12.1 targets MCP spec 2025-11-25, macOS 13+, swift-tools 6.1, `StrictConcurrency`
enabled on the `MCP` target — clean against our Swift 6 strict-concurrency build. Library
deps are modest (swift-system, swift-log, mattt/eventsource); **swift-nio is used only by
the SDK's conformance executable, `import MCP` does not pull it in**. Server API:
`actor Server` + `withMethodHandler(CallTool.self) { … }` closures; ships
`StatefulHTTPServerTransport` with session IDs, POST→SSE, standalone GET SSE, DELETE
teardown, `Last-Event-ID` resumability, and built-in `OriginValidator.localhost()`.

Hand-rolling JSON-RPC + Streamable HTTP semantics (sessions, SSE resumability, protocol
version negotiation) is exactly the kind of subtle surface that erodes reliability.
Pre-1.0 API churn is real → **pin the exact version** in `Package.swift` and treat
upgrades as deliberate changes.

Two SDK pitfalls found in open issues, both avoided by construction:

- **Never use `StatelessHTTPServerTransport`** (issues #254/#255: response waiters keyed
  by raw JSON-RPC id collide across concurrent clients → hangs + leaked continuations;
  `notifications/cancelled` leaves the POST hanging).
- **One `Server` accepts one `initialize`** (#144) → create a fresh
  `Server` + `StatefulHTTPServerTransport` per MCP session via a factory, with an
  idle-session reaper — the SDK's own conformance server
  (`Sources/MCPConformance/Server/HTTPApp.swift`) demonstrates precisely this.

### D3 — HTTP listener: port the SDK's NIO reference vs. hand-rolled NWListener. *(user decision)*

The SDK's HTTP server transport is framework-agnostic: you hand it a parsed
`HTTPRequest {method, headers, body, path}` and write back
`.ok/.data/.stream(AsyncThrowingStream<Data,_>)/.error`. Someone must own the socket +
HTTP/1.1 parsing + SSE flushing:

| | A: `swift-nio`, port `HTTPApp.swift` | B: `NWListener` + hand-rolled HTTP/1.1 |
|---|---|---|
| Reliability | The SDK authors' own tested reference (parsing, chunked bodies, keep-alive, SSE flush, session cleanup loop) — lowest bug surface | We re-implement HTTP parsing and SSE backpressure on `NWConnection`; the SSE path is the classic source of subtle bugs |
| Dependencies | +swift-nio (Apple-maintained, already in the SDK's package graph) | zero new deps; framework we already use (`ReactotronServer`, Mirror) |
| Effort | small (adapt ~300 lines) | moderate (HTTP request parser + SSE writer + tests for both) |

**Recommendation: A.** Reliability is the stated top requirement and NIO is a
well-maintained Apple dependency confined to one target. B is defensible under the repo's
dependency policy — if chosen, budget real test time for chunked/pipelined requests and
SSE teardown, and port `HTTPApp`'s session-lifecycle logic regardless. Either way the
listener hides behind a small protocol so tool/resource logic tests use
`InMemoryTransport` and never touch sockets.

### D4 — Separate MCP command store; UI untouched. *(decided)*

Mirror upstream: `McpCommandStore` is a new ADBKit actor holding its own ring buffer of
raw `ReactotronCommand`s (cap 500 like upstream, **plus a total-byte cap upstream lacks** —
reuse `ReactotronTimeline`'s hysteresis math; a single `image` payload can be megabytes and
64 MiB frames are legal on our relay). It also derives, from the same event stream:
connected clients (intro payloads), the latest `state.values.response` per client, the
per-client custom-command registry, and the subscription list.

Feeding it requires the only change to existing code: `ReactotronService` grows
**multi-subscriber event fan-out** (per-subscriber `AsyncStream` continuations,
`.bufferingNewest` policy so a slow consumer can never back-pressure the relay). The UI
session migrates from consuming the server stream directly to being subscriber #1 — a
small, mechanical change; the alternative (moving retention off the MainActor session)
would refactor a 3,000-line view for no additional capability.

`clear_timeline` clears only the MCP buffer (upstream parity); the UI timeline is separate
state with its own Clear.

### D5 — Contract: match the embedded server exactly, then extend. *(decided)*

Port **4567**, route `/mcp`, the 10 tool names with upstream's input schemas and result
shapes, the 8 resource URIs, `_meta` connection blocks, the 800k/200/500-char caps, the
`[TRUNCATED …]` guidance suffix, the 1.5 s correlation timeout, and `resolveClientId`
error strings. Parity means upstream's docs and any prompts users wrote against desktop
Reactotron work verbatim against Droidective. (Port conflict with an actually-running
Reactotron desktop isn't a real scenario — it would already be fighting us for WS 9090.)

Extensions (clearly ours, additive, v1.5 candidates once parity ships): filterable query
tools in the spirit of npm 0.3.0 (`get_logs(level, contains, limit)`,
`get_network(url, method, status, minDuration, limit)`, a consolidated `get_errors`), and
its five MCP prompts — `debug_app`, `trace_action`, `diagnose_network`,
`debug_performance`, `debug_errors` — which are cheap, high-leverage, and clients surface
as slash commands.

### D6 — Stateful sessions, not upstream's per-request-stateless mode. *(decided)*

Upstream creates a throwaway `McpServer` per POST. That works but forfeits SSE
notifications and resumability, and the Swift SDK's stateless transport is the buggy one
(D2). We use stateful sessions (`MCP-Session-Id`, per-session `Server`, GET SSE stream,
DELETE teardown) with an idle reaper (5 min, configurable). Clients that never open the
GET stream lose nothing.

### D7 — Redaction: port upstream's layer, default-on. *(decided — see §7)*

### D8 — Security posture. *(decided)*

- Bind `127.0.0.1` only, hard-coded — never `0.0.0.0`, regardless of the relay's LAN toggle.
- Keep the SDK's default validation pipeline: `OriginValidator.localhost()` (DNS-rebinding
  defense the MCP spec mandates), Accept/Content-Type/protocol-version/session validators.
- **Feature off by default** — a Settings toggle, like upstream's footer button and
  Figma/Xcode's opt-ins.
- Optional bearer token (SDK ships `BearerTokenValidator`): default **off** for parity and
  frictionless `claude mcp add`; a Settings toggle generates one and the UI shows
  `claude mcp add … -H "Authorization: Bearer <token>"`. Localhost + Origin checks +
  default-on redaction is the same posture upstream and Figma ship; the token covers users
  who want other-local-process isolation.

### D9 — Lifecycle. *(decided)*

- MCP enabled ⇒ `ReactotronService` starts (if not already) and **joins the kept-alive
  set**: `AppState.enterBackground()` currently stops Reactotron on window close; with the
  MCP toggle on, both the relay and the listener stay up (that's the point — the agent
  works while the user isn't looking at the window). Quit teardown stays bounded (existing
  2 s budget): stop listener → DELETE-equivalent close of sessions → relay stop.
- adb reverse for newly-appearing devices must keep running while MCP is on (the session's
  device-list watcher already runs with the view closed; it must also run with MCP on and
  the feature never opened).
- Port 4567 busy ⇒ fail visibly (Settings shows the error + a port override field +
  Retry), never silently pick another port — the copy-paste client config must match
  reality. Single-instance: first app instance binds; a second shows "MCP served by the
  other instance."
- MCP server state surfaces in the Reactotron view header and Settings: Off / Listening on
  4567 / Error(reason), plus a copy button for the `claude mcp add` line and a
  `.mcp.json` snippet.

## 7. Redaction layer (the biggest single work item)

Agents will read network headers, request bodies, and full Redux state — bearer tokens,
session cookies, PII. Upstream treats this as first-class; so do we. Port
`lib/reactotron-mcp/src/redaction.ts` to a pure ADBKit `enum McpRedaction` over
`JSONValue`:

- **Default rules**: ~40 case-insensitive sensitive key names matched at any depth
  (password, token, secret, authorization, cookie, api_key, session, csrf,
  x-forwarded-for, …) + value regexes (Bearer/JWT, `sk-`, `sk-ant-`, `gh[pousr]_`,
  `xox[bpoas]-`, `AKIA`, `AIza`, Stripe keys, PEM private keys). Blocklist model.
- URL query params and form-urlencoded bodies with sensitive param names are redacted;
  JSON embedded in strings is recursively parsed and redacted (depth ≤5, ≤1 MB).
- `statePathPatterns` anchor state-tree redaction using the response's `payload.path`.
- **Two-key opt-out**: the RN app may send `mcpRedaction` in `client.intro`
  (`additionalRules` always honored; `removeRules`/`disableRedaction` honored only if the
  user also enables `allowClientRemoveRules`/`allowClientDisable` in Droidective settings,
  both default off). Resolution cached per clientId; aggregated resources redact each
  app's events under that app's rules.
- Applied **only at the MCP boundary** — the Droidective UI stays unredacted, exactly like
  upstream.
- UI: a shield indicator (green = enforced, amber = a client opted out) + a rules editor in
  the MCP settings — port of upstream's `McpSettingsModal` semantics.

This is pure data-in/data-out → it lives in ADBKit with the heaviest test file of the
feature. Upstream's `lib/reactotron-mcp/test/` cases port directly as fixtures.

## 8. Correlation engine (replacing upstream's polling)

Upstream polls its buffer every 100 ms. We do it event-driven, copying the proven
`JSConsoleClient` patterns (pending-continuation map, early-result buffer, generation
counter): `McpCommandStore.awaitCommand(type:clientId:after:timeout:)` registers a
`CheckedContinuation` resumed by the store's own event loop on the first matching command
whose **arrival time is after the send time** (the protocol has no correlation ids;
the arrival-time gate prevents a stale `state.values.response` from a previous request
satisfying a new one — a race upstream tolerates). Timeout 1.5 s (upstream parity) via a
structured race; every continuation is resumed exactly once (leaked continuations are a
crash in Swift — the JSConsole pattern already handles teardown-resumes-all).

Tool → command mapping (all already supported by `ReactotronService.send/broadcast`):

| Tool | Sends | Awaits | Notes |
|---|---|---|---|
| `dispatch_action` | `state.action.dispatch` | `state.action.complete` | reports `confirmed: true/false` on timeout |
| `request_state` | `state.values.request` | `state.values.response` | description pushes `path` to avoid huge trees |
| `request_state_keys` | `state.keys.request` | `state.keys.response` | |
| `swap_state` | `state.restore.request` | — | fire-and-forget, marked destructive |
| `send_custom_command` | `custom` `{command, args}` | — | |
| `list_custom_commands` | — | — | reads store's registry (from `customCommand.register`) |
| `show_overlay` | `overlay` | — | local file → base64 data URI, PNG/JPEG/GIF, 2 MB cap, dims from header parse |
| `clear_timeline` | — | — | clears MCP buffer only |
| `subscribe_state` / `unsubscribe_state` | `state.values.subscribe` | — | server-global path list, like upstream |

## 9. Reliability engineering — failure modes and mitigations

| Failure mode | Mitigation |
|---|---|
| Port 4567 busy | Visible error + override + retry; never a silent port change (§D9) |
| App not running when client connects | Connection refused; documented ("launch Droidective, enable MCP"); README + Settings copy |
| Slow/stalled MCP consumer back-pressures relay | Fan-out uses `bufferingNewest` per subscriber; relay never awaits subscribers |
| Buffer growth (images, 64 MiB frames) | 500-item cap **and** byte cap with `ReactotronTimeline` hysteresis (improvement over upstream) |
| Oversized tool results blow the client context | 800k-char truncation with actionable `[TRUNCATED …]` guidance (upstream parity) |
| Concurrent clients / session collisions | Stateful transport, per-session `Server` (avoids SDK #144), never Stateless (#254/#255) |
| Session leaks | Idle reaper (HTTPApp pattern); DELETE honored; bounded teardown on quit |
| SSE disconnects | SDK resumability via `Last-Event-ID`; clients auto-reconnect; fresh initialize ⇒ fresh session |
| Correlation races (no protocol ids) | Arrival-after-send gating + single-resume continuations + 1.5 s timeout (§8) |
| Ghost client resurrected by drained `client.intro` (backlog bug) | **Fix first** (guard `.connected` yield on `connections[id] != nil` + test) — MCP's `reactotron://apps` and `resolveClientId` read this state |
| DNS rebinding / cross-origin | 127.0.0.1 bind + `OriginValidator.localhost()` (spec-mandated, SDK default) |
| Sensitive data exfiltration to the agent | Default-on redaction, two-key opt-out (§7) |
| Multiple app instances | First binds; second surfaces a clear status, no crash loop |
| MCP failure taking down the relay | Strict downstream isolation (§5); listener restart button independent of relay |
| SDK pre-1.0 churn | Exact-version pin; upgrades are reviewed changes with the conformance tests re-run |
| Upstream contract drift (they're moving fast: 0.1.0→0.3.0 in 2 days) | Before implementation, re-diff `master` and the npm tarball; record the targeted upstream commit in the test fixtures |

## 10. Module layout

New **library target in the ADBKit package** (keeps the core `ADBKit` target
dependency-free; `swift test` still covers everything):

```
ADBKit/Package.swift            + target ReactotronMCP (deps: ADBKit, MCP swift-sdk [, NIO per D3])
ADBKit/Sources/ReactotronMCP/
  McpCommandStore.swift         actor: ring buffer, derived state, awaitCommand()
  McpRedaction.swift            pure rules engine + DEFAULT_REDACTION_RULES port
  McpSerialization.swift        pure: summaries, previews, 800k truncation + guidance
  McpConstants.swift            caps with upstream's names (BUFFER_SIZE, MAX_RESPONSE_CHARS, …)
  McpToolRegistry.swift         declarative McpToolDef table (the FeatureRegistry pattern, §13)
  McpToolHandlers.swift         the 10 tools over the store + ReactotronService
  McpResources.swift            the 8 resources + timeline/{type} template + completion
  McpSessionFactory.swift       per-session Server + StatefulHTTPServerTransport + reaper
  McpHTTPListener.swift         127.0.0.1 listener → HTTPRequest/HTTPResponse bridge (D3)
  McpServerController.swift     public facade: start/stop/status/config (what App calls)
  UPSTREAM_VERSIONS             pinned upstream commit + npm version the contract targets (§13)
scripts/check-reactotron-upstream.sh   diff contract files vs the pinned commit (§13)
ADBKit/Sources/ADBKit/Services/Reactotron/
  ReactotronService.swift       + event fan-out (the only existing-file change)
ADBKit/Tests/ReactotronMCPTests/  (§11)
App/Sources/...
  Settings ▸ Reactotron MCP section (toggle, port, status, token toggle, redaction
  editor, copy claude-mcp-add / .mcp.json); ReactotronView header status chip;
  AppState keep-alive exemption (D9)
```

App-layer views only render and call `McpServerController` — no Process/adb/parsing, per
the architecture rule. No new `FeatureDef` (this extends `reactotron`); add
`mcp/ai/claude/cursor/agent` to the reactotron feature's keywords so search finds it.

## 11. Testing strategy

Pyramid, all in `swift test`, no device, no network flakes:

1. **Pure units** (largest layer): `McpRedaction` (port upstream's test fixtures; every
   default rule, nesting, embedded-JSON depth, two-key permission matrix),
   `McpSerialization` (truncation boundaries, preview caps, `_meta` blocks), buffer
   trimming (item + byte caps, hysteresis), correlation (timeout, arrival-time gating,
   teardown-resumes-all, no double-resume).
2. **`InMemoryTransport` integration**: real `MCP.Server` with our handlers, scripted
   client — initialize, tools/list (all 10, schemas), each tool round-trip against a
   scripted store, resources/list + read + template completion, resolveClientId error
   strings at 0/2 clients.
3. **Real-socket integration** (pattern: `ReactotronServerTests`): listener on port 0,
   `URLSession` client — initialize + `MCP-Session-Id` echo, POST tool call, GET SSE
   stream, DELETE, evil-Origin → 403, GET on `/mcp` → 405, idle reaping, concurrent
   sessions.
4. **End-to-end**: fake RN client over real WS 9090 (existing test harness) emits
   captured wire frames (`ReactotronCurlTests` fixtures) → MCP client over real HTTP reads
   the redacted `api.response` via `reactotron://network/log` and `request_state`
   round-trips through the fake client.
5. **Live verification** (manual, `verify` skill): debug build + StreamLab RN app +
   `claude mcp add --transport http … && claude --print "list reactotron tools"`;
   confirm Cursor config shape.
6. Registry/engine invariant tests: unaffected (no new feature id).

CI notes: pinned SDK resolves in `swift test`; watch test-time budget (socket tests reuse
the loopback-port-0 pattern that's already fast); warnings-as-errors applies to the new
target from day one.

## 12. Phased plan

| Phase | Content | Gate |
|---|---|---|
| 0 | Fix ghost-client backlog bug; add `ReactotronService` event fan-out; migrate UI session to subscriber API | existing 925 tests + new fan-out/regression tests green |
| 1 | `ReactotronMCP` target skeleton + `McpCommandStore` + `McpSerialization` + **`McpRedaction`**; `UPSTREAM_VERSIONS` + golden contract fixtures + sync-check script (§13) | pure unit suite green (the bulk of new tests) |
| 2 | Tool registry + tools + resources + correlation over `InMemoryTransport` | layer-2 tests green; `tools/list` matches the golden fixture |
| 3 | Listener (per D3) + session factory + validators | socket + E2E suites green |
| 4 | App integration: Settings section, status chip, keep-alive, port-conflict UX, copy-config buttons | `make build` zero warnings; manual verify |
| 5 | Live verification vs Claude Code + Cursor; docs (CLAUDE.md status, site FAQ later); optional v1.5: filter tools + 5 prompts | release gate |

Phases 1–2 are pure logic and parallelize with 3. The redaction port is the single largest
chunk; the listener is the riskiest (hence D3).

## 13. Staying in sync with upstream (maintainability by design)

Upstream is moving fast (npm 0.1.0→0.3.0 in two days; the embedded server landed two
months later). The design absorbs future Reactotron changes cheaply through five
mechanisms, all established in phase 1:

**1. Raw commands in the buffer ⇒ new command types work with zero code.**
`McpCommandStore` stores raw `ReactotronCommand`s, and ADBKit's decoder already routes
unknown types to `.unknown` without dropping the frame. So when Reactotron adds a new
command type, it *automatically* flows into `reactotron://timeline`,
`reactotron://timeline/{type}` (whose type list is derived from buffer contents, not a
hardcoded enum), and any timeline-query tool — queryable by agents the day the RN app
starts emitting it. Code is only needed for typed conveniences: one
`ReactotronCommandType` case + parser case + test (the existing three-line pattern), and
optionally a dedicated tool.

**2. File-for-file mirroring of upstream's package.** The `ReactotronMCP` target layout
(§10) deliberately maps 1:1 onto `lib/reactotron-mcp/src`: `tools.ts` →
`McpToolHandlers.swift`, `resources.ts` → `McpResources.swift`, `redaction.ts` →
`McpRedaction.swift`, `serialization.ts` → `McpSerialization.swift`. An upstream diff
tells you exactly which one Swift file to touch. Constants keep upstream's names
(`BUFFER_SIZE`, `MAX_RESPONSE_CHARS`, …) in one `McpConstants.swift` so cap changes are a
one-line diff.

**3. Declarative tool/resource registry — the repo's own `FeatureRegistry` pattern.**
Tools are not ad-hoc registrations scattered through handler code: a single
`McpToolDef` table (name, description, input schema, handler reference) drives
`tools/list` and dispatch, exactly like `FeatureDef`/`FeatureEngine`. Adding an upstream
tool = one table entry + one handler + one test. Registry-invariant tests copy the
`everyImplementedActionResolvesToARunner` pattern: every def has a handler, every handler
has a def, names are unique.

**4. Golden contract fixtures pinned to an upstream commit.** Check in JSON snapshots of
the advertised contract — the `tools/list` and `resources/list` outputs and the default
redaction rule set — generated against a recorded upstream commit (an `UPSTREAM_VERSIONS`
file in the target: reactotron commit hash + `reactotron-mcp` npm version). A test asserts
our live `tools/list` matches the fixture. Syncing to a new upstream release is then
mechanical: regenerate fixtures, and the failing diff *is* the work list.

**5. A sync-check script, like `scripts/update-bundled-tools.sh`.**
`scripts/check-reactotron-upstream.sh`: shallow-clone upstream, diff the five
contract-defining files (`tools.ts`, `resources.ts`, `redaction.ts`, `serialization.ts`,
`reactotron-core-contract/src/command.ts`) against the commit recorded in
`UPSTREAM_VERSIONS`, plus `npm view reactotron-mcp version` — prints what changed or "in
sync". Run manually before releases (or as a non-blocking scheduled CI job). This turns
"did Reactotron change something?" from archaeology into a 30-second command.

Two guardrails keep the surface *scalable* rather than just syncable: decoding stays
lenient end-to-end (new upstream payload fields are preserved in `JSONValue` and pass
through to agents even before we type them), and the MCP layer's only coupling to the
rest of the app is the `ReactotronService` fan-out — so contract growth never touches the
relay, the UI, or `AppState`.

## 14. Open questions for sign-off

1. **D3**: swift-nio listener (recommended) vs. hand-rolled NWListener HTTP?
2. Default port 4567 (upstream parity, recommended) vs. a Droidective-specific default?
3. Should the MCP toggle live in Settings ▸ Privacy (it's a data-exposure switch) or a new
   Settings ▸ MCP/AI section? (Recommend: its own section, linked from the Reactotron view.)
4. v1.5 extensions (filter tools + prompts) in the first release or a follow-up? (Recommend:
   follow-up; parity first.)
