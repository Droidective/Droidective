import { describe, expect, it } from "vitest"
import { emptyTreeState, treeRows } from "@/lib/json-tree"
import { parseEvent } from "@/lib/reactotron"
import { makeRow, type TimelineRow } from "@/lib/reactotron-rows"
import { copyEventsAsJson, copyLine, copyObject, copyValue } from "@/lib/reactotron-copy"
import type { JsonValue } from "@/lib/json"
import type { ReactotronCommand } from "@/lib/wire"

let nextId = 0
function row(command: ReactotronCommand, receivedAt = 1_700_000_000_000): TimelineRow {
  return makeRow({
    id: nextId++,
    event: parseEvent(command),
    command,
    connection: 2,
    bytes: 40,
    receivedAt,
  })
}

function treeRow(value: JsonValue) {
  // The child row, not the root: a leaf is what "copy value" acts on.
  return treeRows({ v: value }, emptyTreeState())[1]!
}

/**
 * The four copy verbs.
 *
 * The difference between them is the whole point and easy to blur, so each of
 * these asserts the *distinction* rather than just the format.
 */
describe("copyLine", () => {
  it("is the row as read", () => {
    expect(copyLine(row({ type: "log", payload: { level: "warn", message: "slow" } }))).toBe(
      "WARN slow",
    )
  })

  it("carries an api row's status between the badge and the headline", () => {
    const api = row({
      type: "api.response",
      payload: {
        request: { method: "post", url: "https://x.test/v1/cart" },
        response: { status: 500 },
      },
    })
    expect(copyLine(api)).toBe("API 500 POST /v1/cart")
  })

  it("drops the parts a row does not have", () => {
    expect(copyLine(row({ type: "clear" }))).toBe("CLEAR")
  })
})

describe("copyObject", () => {
  it("is the payload as the app sent it, indented and key-sorted", () => {
    // Sorted so two copies of the same payload are the same text — a wire
    // object's key order is whatever the client's serializer felt like.
    expect(copyObject(row({ type: "log", payload: { b: 1, a: { d: 2, c: 3 } } }))).toBe(
      `{\n  "a": {\n    "c": 3,\n    "d": 2\n  },\n  "b": 1\n}`,
    )
  })

  it("is absent for a frame that carried no payload", () => {
    // `clear` and the relay's own notices carry none, and a verb that silently
    // copies "null" is worse than one that is not offered.
    expect(copyObject(row({ type: "clear" }))).toBeNull()
  })
})

describe("copyValue", () => {
  it("hands back a string as itself, not re-escaped", () => {
    // The mistake this catches: running the string through the JSON encoder,
    // so a value the reader can see turns into "\"…\"" with escaped quotes.
    //
    // A *JSON-shaped* string is not the case to test here — the tree grafts one
    // into its object, so the row's value is the object and copying it should
    // give the object. That pair is the last two tests below.
    expect(copyValue(treeRow("plain text"))).toBe("plain text")
    expect(copyValue(treeRow('he said "hi"\nthen left'))).toBe('he said "hi"\nthen left')
  })

  it("indents a structured value", () => {
    expect(copyValue(treeRow({ b: 1, a: 2 }))).toBe('{\n  "a": 2,\n  "b": 1\n}')
  })

  it("renders a scalar as JSON", () => {
    expect(copyValue(treeRow(42))).toBe("42")
    expect(copyValue(treeRow(null))).toBe("null")
    expect(copyValue(treeRow(true))).toBe("true")
  })

  it("copies what a grafted row shows — the object, not the string", () => {
    // A stringified payload renders as its object, so the copy has to be the
    // object too: copying the escaped text from under a rendered tree is the
    // kind of surprise that makes someone stop trusting the button.
    const grafted = treeRows({ body: '{"deep":true}' }, { expanded: new Set(["0"]), raw: new Set() })[1]!
    expect(grafted.isParsed).toBe(true)
    expect(copyValue(grafted)).toBe('{\n  "deep": true\n}')
  })

  it("copies the raw text once the row has been switched back to it", () => {
    const raw = treeRows({ body: '{"deep":true}' }, { expanded: new Set(), raw: new Set(["0"]) })[1]!
    expect(raw.isParsed).toBe(false)
    expect(copyValue(raw)).toBe('{"deep":true}')
  })
})

describe("copyEventsAsJson", () => {
  const rows = [
    row({ type: "log", payload: { level: "error", message: "boom" }, important: true }),
    row({ type: "clear" }),
  ]

  it("is the raw wire commands, with upstream's own field names", () => {
    // Raw rather than enriched: a badge and a headline are this app's rendering
    // choices, and a script reading an export must not come to depend on
    // something that is free to change. What the app sent is not.
    expect(JSON.parse(copyEventsAsJson(rows))).toEqual([
      { type: "log", payload: { level: "error", message: "boom" }, important: true },
      { type: "clear" },
    ])
  })

  it("carries none of the presentation", () => {
    const text = copyEventsAsJson(rows)
    for (const ours of ["badge", "summary", "receivedAt", "connection"]) {
      expect(text, ours).not.toContain(ours)
    }
  })

  it("omits an absent field rather than sending null", () => {
    // So the export reads like the frame that produced it.
    const parsed = JSON.parse(copyEventsAsJson(rows)) as Record<string, unknown>[]
    expect(parsed[1]).toEqual({ type: "clear" })
    expect(parsed[0]).not.toHaveProperty("date")
  })

  it("keeps the client's own date and deltaTime when it sent them", () => {
    const timed = row({ type: "log", date: "2026-08-23T07:00:00.000Z", deltaTime: 12.5 })
    expect(JSON.parse(copyEventsAsJson([timed]))).toEqual([
      { type: "log", date: "2026-08-23T07:00:00.000Z", deltaTime: 12.5 },
    ])
  })

  it("is indented and key-sorted, so two exports of the same events match", () => {
    expect(copyEventsAsJson([row({ type: "log", payload: { b: 1, a: 2 } })])).toBe(
      `[\n  {\n    "payload": {\n      "a": 2,\n      "b": 1\n    },\n    "type": "log"\n  }\n]`,
    )
  })

  it("is valid JSON for an empty selection", () => {
    expect(JSON.parse(copyEventsAsJson([]))).toEqual([])
  })
})
