import { describe, expect, it } from "vitest"

import type { ConsoleRow } from "@/lib/console-feed"
import {
  countLabel,
  currentMatch,
  findMatches,
  nextIndex,
  prevIndex,
  segments,
} from "@/lib/console-find"

function row(id: number, text: string): ConsoleRow {
  return {
    id,
    level: "info",
    type: "log",
    args: [],
    text,
    timestamp: 0,
    source: null,
    local: false,
  }
}

const rows = [row(1, "loading user"), row(2, "boom"), row(3, "User saved"), row(4, "done")]

describe("findMatches", () => {
  it("matches case-insensitively, in feed order", () => {
    expect(findMatches(rows, "user")).toEqual([1, 3])
  })

  it("matches nothing for an empty query, rather than everything", () => {
    // The filter treats empty as "no restriction"; find must not, or opening
    // the bar would mark every row on screen.
    expect(findMatches(rows, "")).toEqual([])
    expect(findMatches(rows, "   ")).toEqual([])
  })

  it("returns nothing when the query is not there", () => {
    expect(findMatches(rows, "zzz")).toEqual([])
  })
})

describe("countLabel", () => {
  it("is blank before anything is typed", () => {
    // "No matches" beside an empty field reads as a broken search.
    expect(countLabel("", [], 0)).toBe("")
  })

  it("says so when a real query finds nothing", () => {
    expect(countLabel("zzz", [], 0)).toBe("No matches")
  })

  it("counts from one", () => {
    expect(countLabel("user", [1, 3], 0)).toBe("1 of 2")
    expect(countLabel("user", [1, 3], 1)).toBe("2 of 2")
  })

  it("clamps an index the feed has outgrown", () => {
    // The feed is live: matches get trimmed while someone is reading, and an
    // index past the end must not read "3 of 2".
    expect(countLabel("user", [1, 3], 9)).toBe("2 of 2")
  })
})

describe("currentMatch", () => {
  it("is null with nothing matched", () => {
    expect(currentMatch([], 0)).toBeNull()
  })

  it("clamps rather than falling off the end", () => {
    expect(currentMatch([1, 3], 9)).toBe(3)
  })
})

describe("stepping", () => {
  it("wraps forward past the last match", () => {
    expect(nextIndex(1, 2)).toBe(0)
  })

  it("wraps backward past the first", () => {
    expect(prevIndex(0, 2)).toBe(1)
  })

  it("clamps a stale index before stepping", () => {
    // From an index the matches no longer reach, the next step is the first
    // match rather than an arbitrary jump.
    expect(nextIndex(9, 3)).toBe(0)
    expect(prevIndex(9, 3)).toBe(1)
  })

  it("stays put with nothing to step through", () => {
    expect(nextIndex(0, 0)).toBe(0)
    expect(prevIndex(0, 0)).toBe(0)
  })
})

describe("segments", () => {
  it("splits a line around the matches", () => {
    expect(segments("a user here", "user")).toEqual([
      { text: "a ", match: false },
      { text: "user", match: true },
      { text: " here", match: false },
    ])
  })

  it("keeps the original casing of what it matched", () => {
    // Rebuilding from the lowercased copy would quietly rewrite every line the
    // highlight touched.
    const found = segments("User and user", "user")
    expect(found.filter((part) => part.match).map((part) => part.text)).toEqual(["User", "user"])
  })

  it("handles a match at each end", () => {
    expect(segments("userx", "user")).toEqual([
      { text: "user", match: true },
      { text: "x", match: false },
    ])
    expect(segments("xuser", "user")).toEqual([
      { text: "x", match: false },
      { text: "user", match: true },
    ])
  })

  it("finds back-to-back matches without swallowing one", () => {
    expect(segments("useruser", "user")).toEqual([
      { text: "user", match: true },
      { text: "user", match: true },
    ])
  })

  it("leaves the text whole when there is no query", () => {
    expect(segments("anything", "")).toEqual([{ text: "anything", match: false }])
  })
})
