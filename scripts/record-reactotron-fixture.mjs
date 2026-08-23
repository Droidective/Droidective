/**
 * Re-record `desktop/src/lib/__fixtures__/reactotron-frames.json`.
 *
 * The desktop analogue of `emulator-harness.sh --record`: it drives the real
 * daemon rather than hand-writing frames, because a hand-made fixture agrees
 * with whatever the parser happens to do while a captured one has already been
 * through Swift's decoder and encoder. `reactotron-wire.test.ts` reads what this
 * writes.
 *
 * It speaks Reactotron's protocol at the relay as a client library would, and
 * saves what comes back out of `/v1/stream`. No device is involved — the relay
 * is a host-side listener and the payloads below are this script's own.
 *
 * Usage:
 *   cd droidectived && swift build
 *   .build/debug/droidectived --port 0 --token-file /tmp/tok    # note the port
 *   node scripts/record-reactotron-fixture.mjs <daemonPort> /tmp/tok
 *
 * Needs `ws` (the browser has WebSocket, Node's built-in client does not speak
 * the daemon's Authorization header as conveniently):
 *   npm install --no-save ws
 *
 * Review the JSON diff rather than editing the fixture: a field that changed
 * shape is exactly what this is meant to surface.
 */
import { readFileSync, writeFileSync } from "node:fs"
import WebSocket from "ws"

const [daemonPort, tokenPath, outPath] = process.argv.slice(2)
if (!daemonPort || !tokenPath) {
  console.error("usage: record-reactotron-fixture.mjs <daemonPort> <tokenFile> [outPath]")
  process.exit(2)
}
const out = outPath ?? "desktop/src/lib/__fixtures__/reactotron-frames.json"
const token = readFileSync(tokenPath, "utf8").trim()

/**
 * One of each frame the timeline has a row for, plus the two that matter most
 * and are easiest to forget: an `important` sent as the client's `"~~~ false
 * ~~~"` sentinel, and a frame that is not JSON at all.
 */
const session = [
  { type: "log", payload: { level: "warn", message: "café ☕" } },
  { type: "log", payload: { level: "error", message: "boom" }, important: "~~~ false ~~~" },
  {
    type: "api.response",
    payload: {
      request: {
        method: "post",
        url: "https://api.example.test/v1/stats?window=7d",
        // A stringified body, which is what `embedded-json.ts` is for.
        data: '{"id":"graphData_v1.3","params":{"storeId":"8052321"}}',
      },
      response: { status: 500, body: "upstream timeout" },
      duration: 812.4,
    },
  },
  { type: "state.action.complete", payload: { name: "user/setName", ms: 1.2 } },
  { type: "state.values.change", payload: { changes: [{ path: "user.name", value: "ada" }] } },
  { type: "asyncStorage.mutation", payload: { action: "setItem", data: { key: "token" } } },
  {
    type: "benchmark.report",
    payload: { title: "startup", steps: [{ title: "mount", time: 12, delta: 12 }] },
  },
  { type: "display", payload: { name: "Session", preview: "3 items", value: { items: 3 } } },
  // No typed case — it must still reach the timeline, under the Saga toggle.
  { type: "saga.task.complete", payload: { name: "fetchUser" } },
]

const items = []
const stream = new WebSocket(`ws://127.0.0.1:${daemonPort}/v1/stream`, {
  headers: { Authorization: `Bearer ${token}` },
})
stream.on("open", () =>
  stream.send(JSON.stringify({ op: "subscribe", id: 1, topic: "reactotron" })),
)
stream.on("message", (raw) => {
  const frame = JSON.parse(raw.toString())
  if (frame.event === "batch") items.push(...frame.items)
  if (frame.event === "failed") {
    console.error("stream failed:", frame.message)
    process.exit(1)
  }
})

// Subscribing is what starts the relay, so the client waits for it.
setTimeout(() => {
  const app = new WebSocket("ws://127.0.0.1:9090")
  app.on("open", () => {
    app.send(
      JSON.stringify({
        type: "client.intro",
        payload: { clientId: "probe", name: "ProbeApp", platform: "android" },
      }),
    )
    for (const frame of session) app.send(JSON.stringify(frame))
    app.send("{not json at all")
    // 1001 — going-away, the close the disconnect notice is keyed on.
    setTimeout(() => app.close(1001, "queue full"), 400)
  })
  app.on("error", (error) => {
    console.error("could not reach the relay on 9090:", error.message)
    console.error("another Reactotron may hold the port — see protocol §5.3.")
    process.exit(1)
  })
}, 500)

setTimeout(() => {
  if (items.length === 0) {
    console.error("nothing captured — is the daemon on that port, with that token?")
    process.exit(1)
  }
  writeFileSync(out, `${JSON.stringify(items, null, 2)}\n`)
  const kinds = items.map((item) => item.kind + (item.command ? `:${item.command.type}` : ""))
  console.log(`wrote ${items.length} envelopes to ${out}`)
  console.log(kinds.join("\n"))
  process.exit(0)
}, 1800)
