import { describe, expect, it } from "vitest"
import {
  filterCrashes,
  formatCrash,
  keptSelection,
  markAfterClear,
  matchesCrash,
  newestUnseen,
  NO_FILTERS,
  presentKinds,
  presentProcesses,
  prunedFilters,
  sameCrashes,
  unclearedCrashes,
} from "@/lib/crashes"
import type { CrashReport } from "@/lib/wire"

function crash(overrides: Partial<CrashReport> & { id: string }): CrashReport {
  return {
    kind: "java",
    kindLabel: "Java exception",
    timestamp: "06-12 10:00:00.000",
    process: "com.example.app",
    pid: 4242,
    title: "java.lang.IllegalStateException: boom",
    raw: "E AndroidRuntime: boom",
    body: "boom",
    ...overrides,
  }
}

// Newest first, as the daemon sends them.
const crashes = [
  crash({ id: "c", timestamp: "06-12 10:00:03.000", title: "ANR in com.other", kind: "anr", kindLabel: "ANR", process: "com.other" }),
  crash({ id: "b", timestamp: "06-12 10:00:02.000", kind: "native", kindLabel: "Native crash", title: "Fatal signal 11 (SIGSEGV)" }),
  crash({ id: "a", timestamp: "06-12 10:00:01.000" }),
]

describe("formatCrash", () => {
  it("wraps the way ADBKit's CrashExtractor does", () => {
    // The fences are a contract with the Mac: the same crash pasted from
    // either app has to arrive in Slack looking the same.
    expect(formatCrash("boom", "plain")).toBe("boom")
    expect(formatCrash("boom", "slack")).toBe("```\nboom\n```")
    expect(formatCrash("boom", "jira")).toBe("{code}\nboom\n{code}")
  })
})

describe("matchesCrash", () => {
  it("matches the title, the process and the raw block, case-insensitively", () => {
    const one = crashes[2] as CrashReport
    expect(matchesCrash(one, "illegalstate")).toBe(true)
    expect(matchesCrash(one, "EXAMPLE")).toBe(true)
    expect(matchesCrash(one, "androidruntime")).toBe(true)
    expect(matchesCrash(one, "nothing here")).toBe(false)
  })

  it("matches everything on an empty or whitespace query", () => {
    const one = crashes[2] as CrashReport
    expect(matchesCrash(one, "")).toBe(true)
    expect(matchesCrash(one, "   ")).toBe(true)
  })

  it("survives a crash that never named a process", () => {
    expect(matchesCrash(crash({ id: "x", process: null }), "example")).toBe(false)
  })
})

describe("filterCrashes", () => {
  it("keeps everything with no filters", () => {
    expect(filterCrashes(crashes, NO_FILTERS)).toHaveLength(3)
  })

  it("narrows by kind, by process, and by both", () => {
    expect(filterCrashes(crashes, { ...NO_FILTERS, kind: "native" }).map((c) => c.id)).toEqual(["b"])
    expect(filterCrashes(crashes, { ...NO_FILTERS, process: "com.other" }).map((c) => c.id)).toEqual(
      ["c"],
    )
    expect(filterCrashes(crashes, { kind: "anr", process: "com.example.app", search: "" })).toEqual(
      [],
    )
  })
})

describe("presentKinds", () => {
  it("offers only the kinds actually present, in first-seen order", () => {
    // A Kind menu listing five options against a one-kind list is a menu whose
    // other four choices all empty the screen.
    expect(presentKinds(crashes)).toEqual([
      { kind: "anr", label: "ANR" },
      { kind: "native", label: "Native crash" },
      { kind: "java", label: "Java exception" },
    ])
  })

  it("offers nothing for an empty list", () => {
    expect(presentKinds([])).toEqual([])
  })
})

describe("presentProcesses", () => {
  it("lists each process once, sorted", () => {
    expect(presentProcesses(crashes)).toEqual(["com.example.app", "com.other"])
  })

  it("skips crashes that named no process", () => {
    expect(presentProcesses([crash({ id: "x", process: null })])).toEqual([])
  })
})

describe("prunedFilters", () => {
  it("drops a filter naming something the list no longer holds", () => {
    // Otherwise the screen goes empty with a Kind menu still claiming to be
    // filtering, and nothing on screen explains why.
    const pruned = prunedFilters(
      { kind: "native", process: "com.gone", search: "boom" },
      [crashes[2] as CrashReport],
    )
    expect(pruned).toEqual({ kind: null, process: null, search: "boom" })
  })

  it("keeps a filter that still matches something", () => {
    const filters = { kind: "anr", process: "com.other", search: "" }
    expect(prunedFilters(filters, crashes)).toEqual(filters)
  })
})

describe("unclearedCrashes", () => {
  it("hides everything at or below the mark", () => {
    // Clearing empties the crash buffer, but the main-buffer fallback can
    // resurface the same crashes on the next fetch.
    const visible = unclearedCrashes(crashes, "S1", {
      serial: "S1",
      mark: "06-12 10:00:02.000",
    })
    expect(visible.map((c) => c.id)).toEqual(["c"])
  })

  it("ignores a mark taken on a different device", () => {
    const visible = unclearedCrashes(crashes, "S2", {
      serial: "S1",
      mark: "06-12 10:00:09.000",
    })
    expect(visible).toHaveLength(3)
  })

  it("keeps a crash with no timestamp rather than guessing", () => {
    // Resurfacing a cleared crash is a smaller harm than hiding a new one.
    const stampless = [crash({ id: "x", timestamp: null })]
    expect(unclearedCrashes(stampless, "S1", { serial: "S1", mark: "99-99" })).toHaveLength(1)
  })

  it("hides nothing without a mark", () => {
    expect(unclearedCrashes(crashes, "S1", null)).toHaveLength(3)
  })
})

describe("markAfterClear", () => {
  it("remembers the newest timestamp present", () => {
    expect(markAfterClear("S1", crashes)).toEqual({ serial: "S1", mark: "06-12 10:00:03.000" })
  })

  it("remembers nothing when there was nothing to compare against", () => {
    expect(markAfterClear("S1", [])).toBeNull()
    expect(markAfterClear("S1", [crash({ id: "x", timestamp: null })])).toBeNull()
  })
})

describe("keptSelection", () => {
  it("keeps a selection that survived the refresh", () => {
    // A watch poll returns the same list every 5 s; a selection that moved
    // under you each time would make the screen unusable.
    expect(keptSelection("b", crashes)).toBe("b")
  })

  it("falls to the first visible crash when the selection is gone", () => {
    expect(keptSelection("gone", crashes)).toBe("c")
    expect(keptSelection(null, crashes)).toBe("c")
  })

  it("selects nothing when nothing is visible", () => {
    expect(keptSelection("b", [])).toBeNull()
  })
})

describe("newestUnseen", () => {
  it("finds the crash that was not there before", () => {
    const before = crashes.slice(1)
    expect(newestUnseen(before, crashes)?.id).toBe("c")
  })

  it("finds nothing when the list is unchanged", () => {
    expect(newestUnseen(crashes, crashes)).toBeNull()
  })

  it("spots an arrival even when the count did not change", () => {
    // One crash ages out of the buffer as another lands: comparing counts
    // would miss it, which is the announcement that matters most.
    const next = [crash({ id: "d", timestamp: "06-12 10:00:04.000" }), ...crashes.slice(0, 2)]
    expect(newestUnseen(crashes, next)?.id).toBe("d")
  })
})

describe("sameCrashes", () => {
  it("is true for an identical list and false once anything moves", () => {
    expect(sameCrashes(crashes, [...crashes])).toBe(true)
    expect(sameCrashes(crashes, crashes.slice(1))).toBe(false)
    expect(sameCrashes(crashes, [...crashes].toReversed())).toBe(false)
  })
})
