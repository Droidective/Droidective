import { describe, expect, it } from "vitest"

import {
  clearPane,
  clearedEmpty,
  emptyPanes,
  toggleSplit,
  visibleIn,
  withPane,
} from "@/lib/reactotron-panes"
import { emptyFilter } from "@/lib/reactotron-filter"
import type { TimelineRow } from "@/lib/reactotron-rows"

function row(id: number): TimelineRow {
  return {
    id,
    event: { kind: "log", level: "debug", message: `m${String(id)}` } as unknown as TimelineRow["event"],
    command: { type: "log" } as unknown as TimelineRow["command"],
    connection: 1,
    important: false,
    bytes: 8,
    receivedAt: 0,
  } as unknown as TimelineRow
}

const rows = [row(1), row(2), row(3), row(4)]

describe("opening and closing the split", () => {
  it("starts unsplit and opens on the toggle", () => {
    expect(emptyPanes().split).toBe(false)
    expect(toggleSplit(emptyPanes()).split).toBe(true)
    expect(toggleSplit(toggleSplit(emptyPanes())).split).toBe(false)
  })

  it("keeps each pane's filter across a close and reopen", () => {
    // Both panes' filters persist: the Mac keeps them, and re-picking two
    // filters every time you glance at one pane would make the split useless.
    const split = toggleSplit(emptyPanes())
    const filtered = withPane(split, 1, { ...split.panes[1], newestFirst: true })
    const reopened = toggleSplit(toggleSplit(filtered))
    expect(reopened.panes[1].newestFirst).toBe(true)
  })

  it("forgets the right pane's clear when the split closes", () => {
    // That pane is going away, so a reopened split offers the whole timeline
    // again — which is also the way back from an accidental clear.
    const split = toggleSplit(emptyPanes())
    const cleared = clearPane(split, 1, rows)
    expect(cleared.panes[1].clearMark).toBe(4)
    expect(toggleSplit(cleared).panes[1].clearMark).toBe(0)
  })

  it("keeps the left pane's clear, because that pane lives on", () => {
    const split = toggleSplit(emptyPanes())
    const cleared = clearPane(split, 0, rows)
    expect(toggleSplit(cleared).panes[0].clearMark).toBe(4)
  })
})

describe("clearing one pane", () => {
  it("hides everything received so far, inclusive of the newest row", () => {
    // Exclusive would leak the last pre-clear row straight back in.
    const cleared = clearPane(toggleSplit(emptyPanes()), 0, rows)
    expect(visibleIn(rows, cleared.panes[0])).toEqual([])
  })

  it("lets new rows through afterwards", () => {
    const cleared = clearPane(toggleSplit(emptyPanes()), 0, rows)
    const after = [...rows, row(5)]
    expect(visibleIn(after, cleared.panes[0]).map((one) => one.id)).toEqual([5])
  })

  it("leaves the other pane untouched", () => {
    // One shared buffer: a delete would empty both, which is why this is a
    // watermark.
    const cleared = clearPane(toggleSplit(emptyPanes()), 0, rows)
    expect(visibleIn(rows, cleared.panes[1])).toHaveLength(4)
  })

  it("clears nothing when there is nothing yet", () => {
    const cleared = clearPane(toggleSplit(emptyPanes()), 0, [])
    expect(cleared.panes[0].clearMark).toBe(0)
    expect(visibleIn(rows, cleared.panes[0])).toHaveLength(4)
  })
})

describe("the cleared empty state", () => {
  it("says a pane is empty because it was cleared, not because nothing came", () => {
    // The setup onboarding would mislead on a live session.
    const cleared = clearPane(toggleSplit(emptyPanes()), 0, rows)
    expect(clearedEmpty(cleared.panes[0], [])).toBe(true)
  })

  it("does not claim that for a pane nobody cleared", () => {
    expect(clearedEmpty(emptyPanes().panes[0], [])).toBe(false)
  })

  it("does not claim it while the pane still has rows", () => {
    const cleared = clearPane(toggleSplit(emptyPanes()), 0, rows)
    expect(clearedEmpty(cleared.panes[0], [row(9)])).toBe(false)
  })
})

describe("a pane's own view", () => {
  it("applies the pane's filter over the shared rows", () => {
    const only = withPane(toggleSplit(emptyPanes()), 0, {
      filter: { ...emptyFilter(), hiddenKinds: ["log"] },
      newestFirst: false,
      clearMark: 0,
    })
    expect(visibleIn(rows, only.panes[0])).toEqual([])
  })

  it("leaves the rows alone with no filter and no clear", () => {
    expect(visibleIn(rows, emptyPanes().panes[0])).toHaveLength(4)
  })
})
