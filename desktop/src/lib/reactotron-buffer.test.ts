import { describe, expect, it } from "vitest"
import {
  applyFrame,
  cleared,
  disconnectNotice,
  dropCount,
  emptyTimeline,
  type Timeline,
} from "@/lib/reactotron-buffer"
import type { JsonValue } from "@/lib/json"
import type { ReactotronFrame } from "@/lib/wire"

const sized = (sizes: number[]) => sizes.map((bytes) => ({ bytes }))
const total = (sizes: number[]) => sizes.reduce((sum, size) => sum + size, 0)

/**
 * Cap enforcement, carried over from ADBKit's `ReactotronTimelineTests`:
 * appends past either cap trim oldest-first, in batches, and always keep the
 * newest row.
 */
describe("dropCount", () => {
  it("drops nothing under both caps", () => {
    const sizes = Array.from({ length: 50 }, () => 10)
    expect(dropCount(sized(sizes), total(sizes), 100, 10_000)).toBe(0)
  })

  it("drops nothing exactly at the caps", () => {
    const sizes = Array.from({ length: 100 }, () => 100)
    expect(dropCount(sized(sizes), total(sizes), 100, 10_000)).toBe(0)
  })

  it("trims a count overflow in one batch, not one row at a time", () => {
    // One row over the cap trims down to the 7/8 low-water mark in a single
    // batch, so a steady stream does not shift the whole array every append.
    const sizes = Array.from({ length: 101 }, () => 1)
    const drop = dropCount(sized(sizes), total(sizes), 100, 1_000_000)
    expect(drop).toBe(101 - (100 - Math.trunc(100 / 8)))
    expect(drop).toBeGreaterThan(1)
  })

  it("trims a byte overflow until it is under budget", () => {
    // 10 × 30 bytes = 300 against a 100-byte budget: trim to the 87-byte
    // low-water mark → 8 oldest dropped, the 2 newest (60 bytes) kept.
    const sizes = Array.from({ length: 10 }, () => 30)
    const drop = dropCount(sized(sizes), total(sizes), 1000, 100)
    expect(drop).toBe(8)
    expect(total(sizes) - total(sizes.slice(0, drop))).toBeLessThanOrEqual(100)
  })

  it("always keeps the newest row, even oversized on its own", () => {
    // A single base64 display image can exceed the whole budget. It evicts
    // everything older and is itself retained — the buffer never trims to
    // empty, because an empty timeline reads as the app having sent nothing.
    expect(dropCount(sized([500, 900]), 1400, 10, 100)).toBe(1)
    expect(dropCount(sized([900]), 900, 10, 100)).toBe(0)
  })

  it("holds both caps across a long stream, newest always surviving", () => {
    let rows: { bytes: number }[] = []
    let bytes = 0
    for (let value = 0; value < 5000; value++) {
      const size = value % 100
      rows = [...rows, { bytes: size }]
      bytes += size
      const drop = dropCount(rows, bytes, 200, 5000)
      if (drop > 0) {
        bytes -= rows.slice(0, drop).reduce((sum, row) => sum + row.bytes, 0)
        rows = rows.slice(drop)
      }
      expect(rows.length).toBeLessThanOrEqual(200)
      expect(bytes).toBeLessThanOrEqual(5000)
      expect(rows.at(-1)?.bytes).toBe(size)
    }
  })
})

function command(connection: number, type: string, payload?: JsonValue, bytes = 40): ReactotronFrame {
  return {
    kind: "command",
    connection,
    bytes,
    command: payload === undefined ? { type } : { type, payload },
  }
}

function intro(connection: number, name: string): ReactotronFrame {
  return {
    kind: "connected",
    connection,
    bytes: 60,
    clientId: name,
    command: { type: "client.intro", payload: { name, platform: "android" } },
  }
}

function fold(frames: ReactotronFrame[], from: Timeline = emptyTimeline()): Timeline {
  return frames.reduce((timeline, frame, index) => applyFrame(timeline, frame, 1000 + index), from)
}

describe("applyFrame", () => {
  it("records the port the relay bound", () => {
    expect(fold([{ kind: "listening", port: 9090 }]).port).toBe(9090)
  })

  it("adds a client and its connect row", () => {
    const timeline = fold([intro(1, "MyApp")])
    expect(timeline.clients).toEqual([{ connection: 1, name: "MyApp", platform: "android" }])
    expect(timeline.rows.map((row) => row.searchText)).toEqual(["connect myapp"])
  })

  it("does not double the app picker when a client re-introduces itself", () => {
    // Upstream's client sends a second intro after a reload; appending would
    // list the same app twice and leave the picker pointing at a stale one.
    const timeline = fold([intro(1, "MyApp"), intro(1, "MyApp")])
    expect(timeline.clients).toHaveLength(1)
    expect(timeline.rows).toHaveLength(2)
  })

  it("keeps rows in the order they arrived, with monotonic ids", () => {
    const timeline = fold([
      command(1, "log", { message: "first" }),
      command(1, "log", { message: "second" }),
    ])
    expect(timeline.rows.map((row) => row.id)).toEqual([0, 1])
    expect(timeline.rows.map((row) => row.searchText)).toEqual(["debug first", "debug second"])
  })

  it("sums the retained bytes so the byte cap has something to spend", () => {
    const timeline = fold([command(1, "log", { message: "a" }, 30), command(1, "log", {}, 12)])
    expect(timeline.totalBytes).toBe(42)
  })

  it("wipes only the sending client's rows on a clear, and leaves no row", () => {
    // One app clearing must not wipe another connected app's timeline, and the
    // clear itself is an instruction rather than an event worth a row.
    const timeline = fold([
      intro(1, "A"),
      intro(2, "B"),
      command(1, "log", { message: "from a" }),
      command(2, "log", { message: "from b" }),
      command(1, "clear"),
    ])
    expect(timeline.rows.map((row) => row.connection)).toEqual([2, 2])
    expect(timeline.rows.some((row) => row.searchText.includes("clear"))).toBe(false)
  })

  it("re-sums the retained bytes after a clear", () => {
    // Otherwise the budget stays spent on rows that no longer exist and the
    // buffer trims live rows to pay for freed ones.
    const timeline = fold([
      command(1, "log", { message: "a" }, 100),
      command(2, "log", { message: "b" }, 30),
      command(1, "clear"),
    ])
    expect(timeline.totalBytes).toBe(30)
  })

  it("trims itself once past the caps", () => {
    // The bound is the whole point of the reducer owning the append: without it
    // a chatty app grows the retained graph until the window stops painting.
    const many = Array.from({ length: 2100 }, (_, i) => command(1, "log", { message: `n${i}` }))
    const timeline = fold(many)
    expect(timeline.rows.length).toBeLessThanOrEqual(2000)
    expect(timeline.rows.at(-1)?.searchText).toBe("debug n2099")
    // The ids keep counting past a trim, so React keys never repeat.
    expect(timeline.nextId).toBe(2100)
    expect(timeline.totalBytes).toBe(timeline.rows.length * 40)
  })
})

describe("applyFrame, when a client goes away", () => {
  it("forgets a client that disconnects and says so in a row", () => {
    const timeline = fold([
      intro(1, "MyApp"),
      { kind: "disconnected", connection: 1, reason: "client closed" },
    ])
    expect(timeline.clients).toEqual([])
    expect(timeline.rows.at(-1)?.searchText).toContain("disconnected")
    // Named after the app, which means it has to be read before the client is
    // forgotten.
    expect(timeline.rows.at(-1)?.searchText).toContain("myapp")
  })

  it("marks the disconnect row important, so it is not filtered past", () => {
    const timeline = fold([intro(1, "A"), { kind: "disconnected", connection: 1, reason: "x" }])
    expect(timeline.rows.at(-1)?.important).toBe(true)
  })

  it("adds no row for a disconnect the transport did not explain", () => {
    // A socket going quiet with no reason is not something to narrate — the
    // client list going empty already says it.
    const timeline = fold([intro(1, "A"), { kind: "disconnected", connection: 1 }])
    expect(timeline.clients).toEqual([])
    expect(timeline.rows).toHaveLength(1)
  })

  it("ignores a frame with nothing in it rather than inventing a row", () => {
    expect(fold([{ kind: "command" }]).rows).toEqual([])
    expect(fold([{ kind: "connected", connection: 1 }]).clients).toEqual([])
    expect(fold([{ kind: "disconnected" }]).rows).toEqual([])
  })
})

describe("cleared", () => {
  it("empties the whole timeline for a null connection", () => {
    const timeline = fold([command(1, "log", {}), command(2, "log", {})])
    expect(cleared(timeline, null).rows).toEqual([])
    expect(cleared(timeline, null).totalBytes).toBe(0)
  })

  it("leaves the clients and the port alone", () => {
    // Clearing the feed is not disconnecting: the app is still there, and the
    // banner must not flip back to "waiting".
    const timeline = fold([{ kind: "listening", port: 9090 }, intro(1, "A")])
    const after = cleared(timeline, null)
    expect(after.clients).toEqual(timeline.clients)
    expect(after.port).toBe(9090)
  })
})

describe("disconnectNotice", () => {
  it("explains a 1001 as the app outpacing the connection, with the fix", () => {
    // The reason this code is carried across the wire at all. 1001 is not "the
    // app quit" — Android's own WebSocket closes going-away once 16 MB are
    // queued, and the fix is in the app's logging.
    const notice = disconnectNotice({ reason: "client closed", code: 1001 }, "MyApp")
    expect(notice?.headline).toContain("MyApp")
    expect(notice?.headline).toContain("1001")
    expect(notice?.detail).toContain("16 MB")
    expect(notice?.detail).toContain("log IDs")
  })

  it("says the ordinary thing for an ordinary close", () => {
    const notice = disconnectNotice({ reason: "client closed", code: 1000 }, "MyApp")
    expect(notice?.headline).toBe("MyApp closed the connection (app reloaded or exited).")
    expect(notice?.detail).toBe(notice?.headline)
  })

  it("names an app it was never told the name of", () => {
    // The explicit `undefined` *is* the case: a client that never sent an intro
    // still disconnects, and the notice has to read without its name.
    // oxlint-disable-next-line unicorn/no-useless-undefined
    expect(disconnectNotice({ reason: "client closed" }, undefined)?.headline).toContain("The app")
  })

  it("has nothing to say when the transport gave no reason", () => {
    expect(disconnectNotice({ code: 1001 }, "MyApp")).toBeNull()
  })
})
