import { describe, expect, it } from "vitest"
import { parseEvent } from "@/lib/reactotron"
import {
  EVENT_KINDS,
  KIND_GROUPS,
  KIND_LABELS,
  makeRow,
  presentation,
  rowKind,
  rowText,
  shortPath,
} from "@/lib/reactotron-rows"
import type { JsonValue } from "@/lib/json"

function shownFor(type: string, payload?: JsonValue) {
  return presentation(parseEvent(payload === undefined ? { type } : { type, payload }))
}

describe("presentation", () => {
  it("badges a connect in green with the app and its environment", () => {
    expect(shownFor("client.intro", { name: "MyApp", environment: "development" })).toEqual({
      badge: "CONNECT",
      badgeTone: "ok",
      primary: "MyApp · development",
      primaryTone: "primary",
    })
  })

  it("tones a log by its level", () => {
    expect(shownFor("log", { level: "debug", message: "x" })).toMatchObject({
      badge: "DEBUG",
      badgeTone: "muted",
    })
    expect(shownFor("log", { level: "warn", message: "x" })).toMatchObject({
      badge: "WARN",
      badgeTone: "warn",
    })
    expect(shownFor("log", { level: "error", message: "x" })).toMatchObject({
      badge: "ERROR",
      badgeTone: "error",
    })
  })

  it("puts an api row's status on the collapsed row", () => {
    // The whole reason the field exists: reading a timeline is mostly looking
    // for the one call that did not return 200, and this saves expanding each.
    const shown = shownFor("api.response", {
      request: { method: "get", url: "https://example.test/v1/users?page=2" },
      response: { status: 500 },
    })
    expect(shown).toMatchObject({
      badge: "API",
      primary: "GET /v1/users?page=2",
      status: 500,
    })
  })

  it("leaves every non-api row without a status", () => {
    expect(shownFor("log", { message: "x" }).status).toBeUndefined()
    expect(shownFor("state.action.complete", { name: "setUser" }).status).toBeUndefined()
  })

  it("gives an unknown frame its own type as the badge", () => {
    expect(shownFor("saga.task.complete", "fetchUser")).toEqual({
      badge: "SAGA.TASK.COMPLETE",
      badgeTone: "muted",
      primary: "fetchUser",
      primaryTone: "muted",
    })
  })

  it("styles the relay's disconnect notice as a warning and does not cut it", () => {
    const notice = "The app hung up — events outpaced the connection. ".repeat(6)
    const shown = presentation({ kind: "unknown", type: "disconnected", payload: notice })
    expect(shown.badge).toBe("DISCONNECTED")
    expect(shown.badgeTone).toBe("warn")
    // Untruncated on purpose: this row is the explanation, and the fix is at
    // the end of the sentence.
    expect(shown.primary).toBe(notice)
  })

  it("bounds an ordinary unknown frame's headline", () => {
    const shown = presentation({ kind: "unknown", type: "noisy", payload: "x".repeat(500) })
    expect(shown.primary).toHaveLength(140)
  })
})

describe("presentation, over the whole event union", () => {
  it("names a state change by its first path, or counts them", () => {
    expect(shownFor("state.values.change", { changes: [{ path: "user.name" }] })).toMatchObject({
      primary: "user.name",
    })
    expect(shownFor("state.values.change", { changes: [{}, {}, {}] })).toMatchObject({
      primary: "",
    })
    expect(shownFor("state.values.change", { changes: [] })).toMatchObject({ primary: "0 changes" })
  })

  it("has a presentation for every event kind the parser can produce", () => {
    // The switch is exhaustive over the union, so this catches the other half:
    // a case that compiles but returns an empty badge.
    for (const type of [
      "client.intro",
      "log",
      "display",
      "image",
      "api.response",
      "benchmark.report",
      "clear",
      "asyncStorage.mutation",
      "state.action.complete",
      "state.values.change",
      "customCommand.register",
      "customCommand.unregister",
      "state.values.response",
      "state.keys.response",
      "state.backup.response",
      "repl.ls.response",
      "repl.execute.response",
      "unrecognized.type",
    ]) {
      expect(shownFor(type).badge, type).not.toBe("")
    }
  })
})

describe("rowKind", () => {
  it("maps each event to the toggle that covers it", () => {
    expect(rowKind(parseEvent({ type: "log" }))).toBe("log")
    expect(rowKind(parseEvent({ type: "client.intro" }))).toBe("connection")
    expect(rowKind(parseEvent({ type: "api.response" }))).toBe("api")
    expect(rowKind(parseEvent({ type: "state.values.change" }))).toBe("subscription")
    expect(rowKind(parseEvent({ type: "asyncStorage.mutation" }))).toBe("asyncStorage")
  })

  it("finds the saga toggle for a frame with no typed case", () => {
    // Sagas arrive as `unknown`, so the kind is read off the wire type — the
    // one place the filter has to look past the parser.
    expect(rowKind(parseEvent({ type: "saga.task.complete" }))).toBe("saga")
  })

  it("puts the disconnect notice under Connection, with the connects", () => {
    expect(rowKind({ kind: "unknown", type: "disconnected", payload: "gone" })).toBe("connection")
  })

  it("leaves the events no toggle covers unfilterable, so they always show", () => {
    expect(rowKind(parseEvent({ type: "repl.ls.response" }))).toBeNull()
    expect(rowKind(parseEvent({ type: "customCommand.register" }))).toBeNull()
    expect(rowKind(parseEvent({ type: "state.values.response" }))).toBeNull()
    expect(rowKind(parseEvent({ type: "anything.else" }))).toBeNull()
  })
})

describe("the kind table", () => {
  it("labels every kind", () => {
    for (const kind of EVENT_KINDS) expect(KIND_LABELS[kind]).toBeTruthy()
  })

  it("puts every kind in exactly one filter group", () => {
    // The dialog is built from the groups, so a kind missing from them is a
    // toggle nobody can reach and a filter nobody can turn back off.
    const grouped = KIND_GROUPS.flatMap((group) => group.kinds)
    expect(grouped.toSorted()).toEqual([...EVENT_KINDS].toSorted())
    expect(new Set(grouped).size).toBe(grouped.length)
  })
})

describe("shortPath", () => {
  it("keeps the path and a trimmed query", () => {
    expect(shortPath("https://api.example.test/v1/users")).toBe("/v1/users")
    expect(shortPath("https://api.example.test/v1/users?page=2&sort=name")).toBe(
      "/v1/users?page=2&sort=name",
    )
    expect(shortPath("https://api.example.test")).toBe("/")
  })

  it("trims a long query rather than letting it push the row", () => {
    const long = shortPath(`https://x.test/a?q=${"y".repeat(200)}`)
    // "/a" + "?" + the first 60 characters of the query, "q=" included.
    expect(long).toBe(`/a?q=${"y".repeat(58)}`)
  })

  it("leaves a string that is not an absolute url exactly as the app sent it", () => {
    expect(shortPath("/relative/path")).toBe("/relative/path")
    expect(shortPath("not a url")).toBe("not a url")
    expect(shortPath("")).toBe("")
  })
})

describe("makeRow", () => {
  const args = {
    id: 7,
    command: { type: "log", payload: { message: "Slow Render" } },
    connection: 2,
    bytes: 41,
    receivedAt: 1000,
  }

  it("lowercases the badge and headline once, for filtering", () => {
    const row = makeRow({ ...args, event: parseEvent(args.command) })
    expect(row.searchText).toBe("debug slow render")
  })

  it("bounds the search text so a long headline is not stored twice over", () => {
    // A `display` names itself, and a REPL response lists a whole store's keys
    // — neither is capped upstream of the row, so the row caps it. Logs are
    // already cut to 500 by the parser, which is why they are not the case to
    // test here.
    const command = { type: "display", payload: { name: "x".repeat(5000) } }
    const row = makeRow({ ...args, command, event: parseEvent(command) })
    expect(row.searchText).toHaveLength(2000)
  })

  it("carries the frame's importance", () => {
    const command = { type: "log", important: true }
    expect(makeRow({ ...args, command, event: parseEvent(command) }).important).toBe(true)
    expect(makeRow({ ...args, event: parseEvent(args.command) }).important).toBe(false)
  })
})

describe("rowText", () => {
  it("joins the badge, status and headline, skipping what is absent", () => {
    expect(rowText({ badge: "API", badgeTone: "type", primary: "GET /x", primaryTone: "primary", status: 200 })).toBe(
      "API 200 GET /x",
    )
    expect(rowText({ badge: "CLEAR", badgeTone: "muted", primary: "", primaryTone: "muted" })).toBe(
      "CLEAR",
    )
  })
})
