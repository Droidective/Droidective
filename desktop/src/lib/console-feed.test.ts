/**
 * The console's rows and the rules over them.
 *
 * Everything here is what the socket cannot test: the buffer's bound, the
 * filter, and the mapping from CDP's console types to the four levels someone
 * actually filters by.
 */

import { describe, expect, it } from "vitest"

import {
  appended,
  filtered,
  levelCounts,
  levelOf,
  localRow,
  MAX_ROWS,
  rowFromCall,
  rowFromException,
  rowText,
  sourceOf,
  toggleLevel,
  type ConsoleRow,
  type Level,
} from "@/lib/console-feed"

function row(id: number, level: Level, text: string): ConsoleRow {
  return { id, level, type: "log", args: [], text, timestamp: 0, source: null, local: false }
}

describe("levelOf", () => {
  it("maps CDP's console types onto the four levels", () => {
    expect(levelOf("error")).toBe("error")
    expect(levelOf("warning")).toBe("warning")
    expect(levelOf("log")).toBe("info")
    expect(levelOf("info")).toBe("info")
    expect(levelOf("debug")).toBe("verbose")
    expect(levelOf("trace")).toBe("verbose")
  })

  it("treats assert as an error, the way Chrome does", () => {
    expect(levelOf("assert")).toBe("error")
  })

  it("accepts warn as well as warning", () => {
    // Chrome sends "warning"; some runtimes send "warn".
    expect(levelOf("warn")).toBe("warning")
  })

  it("keeps an unknown type rather than dropping the line", () => {
    // A level this does not know is still a line someone printed.
    expect(levelOf("dir")).toBe("info")
    expect(levelOf("table")).toBe("info")
    expect(levelOf("something-new")).toBe("info")
  })
})

function frame(url: string, lineNumber: number) {
  return { functionName: "f", url, lineNumber, columnNumber: 0 }
}

describe("sourceOf", () => {
  it("names the first frame the app itself owns", () => {
    const call = {
      type: "log",
      args: [],
      timestamp: 0,
      stackTrace: {
        callFrames: [
          frame("http://localhost:8081/node_modules/react/index.js", 10),
          frame("http://localhost:8081/src/App.tsx", 41),
        ],
      },
    }
    // node_modules is skipped the way Chrome ignore-lists it, and the line is
    // reported 1-based even though CDP counts from zero.
    expect(sourceOf(call)).toBe("App.tsx:42")
  })

  it("ignores a frame with no url", () => {
    const call = {
      type: "log",
      args: [],
      timestamp: 0,
      stackTrace: { callFrames: [frame("", 1), frame("http://localhost:8081/a/B.js", 0)] },
    }
    expect(sourceOf(call)).toBe("B.js:1")
  })

  it("strips a Metro cache-busting query", () => {
    const call = {
      type: "log",
      args: [],
      timestamp: 0,
      stackTrace: { callFrames: [frame("http://localhost:8081/src/App.tsx?hash=abc", 0)] },
    }
    expect(sourceOf(call)).toBe("App.tsx:1")
  })

  it("answers nothing when there is no stack at all", () => {
    expect(sourceOf({ type: "log", args: [], timestamp: 0 })).toBe(null)
  })

  it("answers nothing when every frame is a dependency", () => {
    const call = {
      type: "log",
      args: [],
      timestamp: 0,
      stackTrace: { callFrames: [frame("http://x/node_modules/a.js", 1)] },
    }
    expect(sourceOf(call)).toBe(null)
  })
})

describe("appended", () => {
  it("keeps the newest when the buffer is full", () => {
    const existing = Array.from({ length: 5 }, (_, index) => row(index, "info", `old ${index}`))
    const next = appended(existing, [row(99, "info", "new")], 5)
    expect(next).toHaveLength(5)
    expect(next.at(-1)?.text).toBe("new")
    expect(next[0]?.text).toBe("old 1")
  })

  it("does nothing for an empty batch", () => {
    const existing = [row(1, "info", "a")]
    expect(appended(existing, [])).toEqual(existing)
  })

  it("takes only the tail when one batch alone overflows", () => {
    const burst = Array.from({ length: 12 }, (_, index) => row(index, "info", `b${index}`))
    const next = appended([], burst, 5)
    expect(next.map((one) => one.text)).toEqual(["b7", "b8", "b9", "b10", "b11"])
  })

  it("bounds the buffer at something a console can still scroll", () => {
    expect(MAX_ROWS).toBeGreaterThan(500)
    expect(MAX_ROWS).toBeLessThanOrEqual(20_000)
  })
})

describe("filtered", () => {
  const rows = [
    row(1, "info", "hello world"),
    row(2, "error", "boom"),
    row(3, "warning", "careful"),
    row(4, "verbose", "chatty"),
  ]

  it("shows everything when no level is ticked", () => {
    // A filter bar with nothing ticked showing nothing is a console that looks
    // broken, so an empty set means "all".
    expect(filtered(rows, { levels: new Set(), query: "" })).toHaveLength(4)
  })

  it("shows only the ticked levels", () => {
    const shown = filtered(rows, { levels: new Set<Level>(["error", "warning"]), query: "" })
    expect(shown.map((one) => one.id)).toEqual([2, 3])
  })

  it("matches the query case-insensitively", () => {
    expect(filtered(rows, { levels: new Set(), query: "WORLD" }).map((one) => one.id)).toEqual([1])
  })

  it("ignores surrounding whitespace in the query", () => {
    expect(filtered(rows, { levels: new Set(), query: "  boom  " }).map((one) => one.id)).toEqual([
      2,
    ])
  })

  it("combines the level and the query", () => {
    const shown = filtered(rows, { levels: new Set<Level>(["error"]), query: "hello" })
    expect(shown).toEqual([])
  })
})

describe("toggleLevel", () => {
  it("ticks and unticks", () => {
    const on = toggleLevel(new Set(), "error")
    expect(on.has("error")).toBe(true)
    expect(toggleLevel(on, "error").has("error")).toBe(false)
  })

  it("does not mutate what it was given", () => {
    const before = new Set<Level>(["error"])
    toggleLevel(before, "info")
    expect([...before]).toEqual(["error"])
  })
})

describe("levelCounts", () => {
  it("counts every level, including the empty ones", () => {
    const counts = levelCounts([row(1, "error", "a"), row(2, "error", "b"), row(3, "info", "c")])
    expect(counts).toEqual({ verbose: 0, info: 1, warning: 0, error: 2 })
  })
})

describe("rows from CDP", () => {
  it("takes a console call's level, text and time", () => {
    const made = rowFromCall(7, {
      type: "warning",
      args: [{ type: "string", value: "watch out" }],
      timestamp: 1_700_000_000_000,
    })
    expect(made).toMatchObject({ id: 7, level: "warning", text: "watch out", local: false })
  })

  it("reads an exception as an error carrying its own text", () => {
    const made = rowFromException(3, { text: "Uncaught TypeError" }, 5)
    expect(made.level).toBe("error")
    expect(made.text).toBe("Uncaught TypeError")
  })

  it("marks a row this app wrote", () => {
    expect(localRow(1, "info", "› 1 + 1", 0).local).toBe(true)
  })
})

describe("rowText", () => {
  it("is one line with the time, the level and the source", () => {
    const made: ConsoleRow = { ...row(1, "error", "boom"), timestamp: 0, source: "App.tsx:4" }
    expect(rowText(made)).toBe("00:00:00.000 [error] boom (App.tsx:4)")
  })

  it("omits the source when there is none", () => {
    expect(rowText(row(1, "info", "hi"))).toBe("00:00:00.000 [info] hi")
  })
})
