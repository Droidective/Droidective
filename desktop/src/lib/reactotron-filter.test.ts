import { describe, expect, it } from "vitest"
import { parseEvent } from "@/lib/reactotron"
import { makeRow, EVENT_KINDS, type TimelineRow } from "@/lib/reactotron-rows"
import {
  decodeHiddenKinds,
  emptyFilter,
  encodeHiddenKinds,
  filterRows,
  isFiltering,
  seenMethods,
  statusClass,
  statusLabel,
  statusTone,
} from "@/lib/reactotron-filter"
import type { JsonValue } from "@/lib/json"

let nextId = 0
function row(type: string, payload?: JsonValue, connection = 1): TimelineRow {
  const command = payload === undefined ? { type } : { type, payload }
  return makeRow({
    id: nextId++,
    event: parseEvent(command),
    command,
    connection,
    bytes: 40,
    receivedAt: 0,
  })
}

function api(method: string, status: number, url = "https://x.test/a"): TimelineRow {
  return row("api.response", { request: { method, url }, response: { status } })
}

describe("statusClass", () => {
  it("buckets a code by its hundreds digit", () => {
    expect(statusClass(200)).toBe(2)
    expect(statusClass(301)).toBe(3)
    expect(statusClass(404)).toBe(4)
    expect(statusClass(503)).toBe(5)
  })

  it("keeps status 0 as its own bucket", () => {
    // A request that never got a response arrives as 0 from the client, and
    // "Failed" is the thing a reader most often wants to filter to.
    expect(statusClass(0)).toBe(0)
    expect(statusLabel(0)).toBe("Failed")
    expect(statusLabel(4)).toBe("4xx")
  })

  it("has no bucket for 1xx or for nonsense", () => {
    expect(statusClass(100)).toBeNull()
    expect(statusClass(999)).toBeNull()
    expect(statusClass(-1)).toBeNull()
  })
})

describe("statusTone", () => {
  it("tones success, client error and server error apart", () => {
    expect(statusTone(200)).toBe("ok")
    expect(statusTone(404)).toBe("warn")
    expect(statusTone(500)).toBe("error")
  })

  it("leaves a redirect and a failure neutral", () => {
    // Only the code is toned at all — colouring more would drown the badge
    // colours a reader actually scans by.
    expect(statusTone(302)).toBe("neutral")
    expect(statusTone(0)).toBe("neutral")
  })
})

describe("filterRows", () => {
  const rows = [
    row("log", { level: "debug", message: "starting up" }),
    row("log", { level: "error", message: "boom" }),
    api("GET", 200),
    api("POST", 500),
    row("state.action.complete", { name: "setUser" }),
    row("repl.ls.response", ["a"]),
  ]

  it("shows everything by default", () => {
    expect(filterRows(rows, emptyFilter())).toHaveLength(rows.length)
    expect(isFiltering(emptyFilter())).toBe(false)
  })

  it("hides what you untick, not the other way round", () => {
    // Upstream's model, and the Mac's: the set names what is *hidden*, so a
    // filter nobody has touched needs no default and a kind added later shows
    // without a migration.
    const visible = filterRows(rows, { ...emptyFilter(), hiddenKinds: ["log", "api"] })
    expect(visible.map((item) => item.event.kind)).toEqual(["stateAction", "replKeys"])
  })

  it("keeps showing the events no toggle covers", () => {
    // A REPL response has no kind, so hiding every kind there is must still
    // leave it visible rather than blanking the feed.
    const visible = filterRows(rows, { ...emptyFilter(), hiddenKinds: [...EVENT_KINDS] })
    expect(visible.map((item) => item.event.kind)).toEqual(["replKeys"])
  })

  it("narrows to one HTTP method, dropping the non-api rows with it", () => {
    const visible = filterRows(rows, { ...emptyFilter(), method: "POST" })
    expect(visible).toHaveLength(1)
    expect(visible[0]?.event).toMatchObject({ method: "POST", status: 500 })
  })

  it("narrows to a status bucket", () => {
    expect(filterRows(rows, { ...emptyFilter(), status: 5 })).toHaveLength(1)
    expect(filterRows(rows, { ...emptyFilter(), status: 3 })).toHaveLength(0)
  })

  it("drops an api row whose status falls in no bucket", () => {
    const odd = [api("GET", 100)]
    expect(filterRows(odd, { ...emptyFilter(), status: 2 })).toHaveLength(0)
    expect(filterRows(odd, emptyFilter())).toHaveLength(1)
  })

  it("searches the badge and the headline, case- and space-insensitively", () => {
    expect(filterRows(rows, { ...emptyFilter(), search: "BOOM" })).toHaveLength(1)
    expect(filterRows(rows, { ...emptyFilter(), search: "  error " })).toHaveLength(1)
    expect(filterRows(rows, { ...emptyFilter(), search: "setuser" })).toHaveLength(1)
    expect(filterRows(rows, { ...emptyFilter(), search: "nothing here" })).toHaveLength(0)
  })

  it("applies every refinement at once", () => {
    const visible = filterRows(rows, {
      hiddenKinds: ["log"],
      method: "GET",
      status: 2,
      search: "api",
    })
    expect(visible).toHaveLength(1)
  })

  it("reports itself active only when it is doing something", () => {
    // Drives the toolbar's dot. A typed query is not "filtering" for this
    // purpose — the search box shows its own state.
    expect(isFiltering({ ...emptyFilter(), search: "x" })).toBe(false)
    expect(isFiltering({ ...emptyFilter(), hiddenKinds: ["log"] })).toBe(true)
    expect(isFiltering({ ...emptyFilter(), method: "GET" })).toBe(true)
    expect(isFiltering({ ...emptyFilter(), status: 4 })).toBe(true)
  })
})

describe("seenMethods", () => {
  it("offers only the methods the app actually sent", () => {
    const rows = [api("POST", 200), api("GET", 200), api("POST", 201), row("log")]
    expect(seenMethods(rows, null)).toEqual(["GET", "POST"])
  })

  it("keeps a restored selection in the list before its first row arrives", () => {
    // A relaunch starts with an empty buffer, and a picker that cannot show its
    // own active selection reads as broken.
    expect(seenMethods([], "PATCH")).toEqual(["PATCH"])
  })
})

describe("the persisted hidden set", () => {
  it("stores the same selection as the same bytes", () => {
    expect(encodeHiddenKinds(["log", "api"])).toBe("api,log")
    expect(encodeHiddenKinds(["api", "log"])).toBe("api,log")
  })

  it("round-trips", () => {
    const kinds = ["api", "log", "saga"] as const
    expect(decodeHiddenKinds(encodeHiddenKinds([...kinds]), EVENT_KINDS)).toEqual([...kinds])
  })

  it("drops a name it no longer knows", () => {
    // A kind renamed or removed since would otherwise persist as a filter
    // nothing on screen can turn back off.
    expect(decodeHiddenKinds("log,retired,api", EVENT_KINDS)).toEqual(["api", "log"])
  })

  it("reads an empty string as nothing hidden", () => {
    expect(decodeHiddenKinds("", EVENT_KINDS)).toEqual([])
  })
})
