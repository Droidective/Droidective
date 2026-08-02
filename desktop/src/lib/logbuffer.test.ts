import { describe, expect, it } from "vitest"
import { emptyBuffer, matchesFilter, withGap, withLines } from "@/lib/logbuffer"
import type { LogRow } from "@/lib/logbuffer"
import type { LogLine } from "@/lib/wire"

function line(message: string, overrides: Partial<LogLine> = {}): LogLine {
  return {
    time: "01-01 00:00:00.000",
    pid: "1234",
    tid: "1234",
    level: "I",
    tag: "Tag",
    message,
    ...overrides,
  }
}

const messages = (rows: LogRow[]): string[] =>
  rows.map((row) => (row.kind === "line" ? row.line.message : `gap:${row.count}`))

describe("withLines", () => {
  it("appends in order", () => {
    const buffer = withLines(withLines(emptyBuffer(), [line("a")]), [line("b"), line("c")])
    expect(messages(buffer.rows)).toEqual(["a", "b", "c"])
  })

  it("gives every row a key that stays unique across a trim", () => {
    let buffer = emptyBuffer()
    for (let index = 0; index < 10; index += 1) {
      buffer = withLines(buffer, [line(`line ${index}`)], 4)
    }
    const keys = buffer.rows.map((row) => row.key)
    expect(new Set(keys).size).toBe(keys.length)
    expect(keys).toEqual(keys.toSorted((a, b) => a - b))
  })

  it("is a no-op for an empty batch", () => {
    const buffer = emptyBuffer()
    expect(withLines(buffer, [])).toBe(buffer)
  })

  it("drops the oldest rows past capacity", () => {
    const buffer = withLines(emptyBuffer(), [line("a"), line("b"), line("c")], 2)
    expect(messages(buffer.rows)).toEqual(["b", "c"])
  })

  it("survives a batch larger than the whole buffer", () => {
    const buffer = withLines(emptyBuffer(), [line("a"), line("b"), line("c"), line("d")], 2)
    expect(messages(buffer.rows)).toEqual(["c", "d"])
  })
})

describe("withGap", () => {
  it("records what the daemon dropped as a visible row", () => {
    const buffer = withGap(withLines(emptyBuffer(), [line("a")]), 12)
    expect(messages(buffer.rows)).toEqual(["a", "gap:12"])
    expect(buffer.dropped).toBe(12)
  })

  it("merges consecutive gaps into one marker", () => {
    // Two `dropped` events back to back are one interruption to a reader;
    // stacking markers would bury the lines around them.
    const buffer = withGap(withGap(withLines(emptyBuffer(), [line("a")]), 5), 7)
    expect(messages(buffer.rows)).toEqual(["a", "gap:12"])
    expect(buffer.dropped).toBe(12)
  })

  it("starts a new marker once more lines have arrived", () => {
    let buffer = withLines(emptyBuffer(), [line("a")])
    buffer = withGap(buffer, 5)
    buffer = withLines(buffer, [line("b")])
    buffer = withGap(buffer, 7)
    expect(messages(buffer.rows)).toEqual(["a", "gap:5", "b", "gap:7"])
    expect(buffer.dropped).toBe(12)
  })

  it("ignores a gap of nothing", () => {
    const buffer = withLines(emptyBuffer(), [line("a")])
    expect(withGap(buffer, 0)).toBe(buffer)
  })

  it("keeps counting drops even after the marker rows are trimmed away", () => {
    let buffer = withGap(emptyBuffer(), 3)
    buffer = withLines(buffer, [line("a"), line("b")], 2)
    expect(messages(buffer.rows)).toEqual(["a", "b"])
    expect(buffer.dropped).toBe(3)
  })
})

describe("matchesFilter", () => {
  const row: LogRow = { kind: "line", key: 0, line: line("Boot completed", { tag: "ActivityManager" }) }

  it("matches the tag and the message, case-insensitively", () => {
    expect(matchesFilter(row, "activitymanager")).toBe(true)
    expect(matchesFilter(row, "BOOT")).toBe(true)
    expect(matchesFilter(row, "nope")).toBe(false)
  })

  it("matches everything for an empty filter", () => {
    expect(matchesFilter(row, "")).toBe(true)
    expect(matchesFilter(row, "  ")).toBe(true)
  })

  it("never filters out a gap", () => {
    // Hiding the marker would turn a visible interruption back into a silent
    // one, which is exactly what it exists to prevent.
    const gap: LogRow = { kind: "gap", key: 1, count: 9 }
    expect(matchesFilter(gap, "activitymanager")).toBe(true)
  })
})
