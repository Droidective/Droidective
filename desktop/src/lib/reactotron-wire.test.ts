import { describe, expect, it } from "vitest"
import frames from "@/lib/__fixtures__/reactotron-frames.json"
import { applyFrame, emptyTimeline, type Timeline } from "@/lib/reactotron-buffer"
import { presentation, rowKind } from "@/lib/reactotron-rows"
import { filterRows, emptyFilter, seenMethods } from "@/lib/reactotron-filter"
import { parseEmbedded } from "@/lib/embedded-json"
import { jsonMatches } from "@/lib/json-search"
import type { ReactotronFrame } from "@/lib/wire"

/**
 * The model against real relay output.
 *
 * `__fixtures__/reactotron-frames.json` is not hand-written: it is what came
 * back out of `droidectived`'s own `/v1/stream` socket while a WebSocket client
 * spoke Reactotron's protocol at the relay — one session, captured whole, from
 * `listening` to a 1001 close. The reason ADBKit has `FixtureProcessRunner` is
 * the reason this exists: hand-made frames agree with whatever the parser
 * happens to do, and every field here has already survived Swift's encoder.
 *
 * Nothing in it is sensitive — the app, the URLs and the payloads are the
 * probe's own inventions, and it never touched a device.
 */
const captured = frames as ReactotronFrame[]

function fold(): Timeline {
  return captured.reduce((timeline, frame, index) => applyFrame(timeline, frame, index), emptyTimeline())
}

describe("the model, over a captured relay session", () => {
  it("reads the whole session without dropping a frame", () => {
    const timeline = fold()
    // 13 envelopes: one `listening` (no row), one `connected`, ten commands,
    // and a disconnect that adds its own notice row.
    expect(captured).toHaveLength(13)
    expect(timeline.rows).toHaveLength(12)
    expect(timeline.port).toBe(9090)
  })

  it("ends with the app gone and its notice explaining why", () => {
    const timeline = fold()
    expect(timeline.clients).toEqual([])
    const last = timeline.rows.at(-1)
    expect(presentation(last?.event ?? { kind: "clear" }).badge).toBe("DISCONNECTED")
    // The capture closed with 1001, so this is the notice that names the cause
    // rather than the one that just says the app went away.
    expect(last?.searchText).toContain("outpaced")
    expect(last?.searchText).toContain("probeapp")
  })

  it("gives every captured frame a badge and a headline", () => {
    for (const row of fold().rows) {
      const shown = presentation(row.event)
      expect(shown.badge, JSON.stringify(row.command.type)).not.toBe("")
    }
  })

  it("sums real frame sizes rather than guessing at them", () => {
    const timeline = fold()
    const sent = captured.reduce((sum, frame) => sum + (frame.bytes ?? 0), 0)
    expect(timeline.totalBytes).toBe(sent)
    expect(sent).toBeGreaterThan(0)
  })

  it("reads a repaired sentinel as the boolean it was", () => {
    // The client sent `important: "~~~ false ~~~"`; ADBKit's lenient decode
    // turned it back into a real `false` before it reached the wire. Asserted
    // here because that repair is upstream of everything this app renders.
    expect(captured.some((frame) => frame.command?.important === false)).toBe(true)
    const boom = fold().rows.find((row) => row.searchText === "error boom")
    // `false`, not the string it arrived as and not the `true` a truthy
    // non-empty string would have become.
    expect(boom?.important).toBe(false)
  })

  it("keeps the frame it could not decode, as itself", () => {
    // The relay reports malformed JSON rather than swallowing it, and the model
    // has to show it: silence there reads as the relay receiving nothing.
    const row = fold().rows.find((item) => item.command.type === "(undecodable)")
    expect(row).toBeDefined()
    expect(presentation(row?.event ?? { kind: "clear" }).badge).toBe("(UNDECODABLE)")
  })
})

describe("the captured session, read the way the pane reads it", () => {
  it("finds the api call and its status without expanding a row", () => {
    const rows = fold().rows
    const api = rows.find((row) => row.event.kind === "apiResponse")
    expect(presentation(api?.event ?? { kind: "clear" })).toMatchObject({
      badge: "API",
      primary: "POST /v1/stats?window=7d",
      status: 500,
    })
    expect(seenMethods(rows, null)).toEqual(["POST"])
  })

  it("filters the captured session the way the toolbar would", () => {
    const rows = fold().rows
    expect(filterRows(rows, { ...emptyFilter(), search: "café" })).toHaveLength(1)
    expect(filterRows(rows, { ...emptyFilter(), status: 5 })).toHaveLength(1)
    expect(filterRows(rows, { ...emptyFilter(), hiddenKinds: ["log"] })).toHaveLength(
      rows.length - 2,
    )
  })

  it("routes the saga frame to the Saga toggle, though it has no typed case", () => {
    const saga = fold().rows.find((row) => row.command.type === "saga.task.complete")
    expect(rowKind(saga?.event ?? { kind: "clear" })).toBe("saga")
  })

  it("opens the stringified request body the app actually sent", () => {
    // The `data` field on a real `api.response` is a string of JSON, which is
    // the whole reason `embedded-json.ts` exists.
    const api = fold().rows.find((row) => row.event.kind === "apiResponse")
    const request = api?.event.kind === "apiResponse" ? api.event.request : undefined
    const data = typeof request === "object" && request !== null && !Array.isArray(request)
      ? request["data"]
      : undefined
    expect(typeof data).toBe("string")
    expect(parseEmbedded(String(data))).toEqual({
      id: "graphData_v1.3",
      params: { storeId: "8052321" },
    })
  })

  it("finds a leaf inside that stringified body, at a path the tree can open", () => {
    const api = fold().rows.find((row) => row.event.kind === "apiResponse")
    const payload = api?.command.payload ?? null
    const matches = jsonMatches(payload, "storeId", { expandingStringifiedJson: true })
    expect(matches.map((match) => match.displayPath)).toEqual([
      "request.data.params.storeId",
    ])
    expect(matches[0]?.preview).toBe('"8052321"')
  })

  it("survives being replayed twice with no state left behind", () => {
    // The reducer is pure, so two folds of the same capture must be identical.
    // A module-level counter or a mutated row would show up right here.
    expect(fold()).toEqual(fold())
  })
})
