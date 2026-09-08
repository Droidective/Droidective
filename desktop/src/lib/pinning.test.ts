import { describe, expect, it } from "vitest"
import { clampedTarget, dropLanding, markerSlot, normalizePinned } from "@/lib/pinning"
import { reorderTabs, tabState } from "@/lib/tabs"
import {
  closable,
  closeOthers,
  drop,
  isPinned,
  move,
  newWorkspace,
  open,
  pin,
  pinnedTabs,
  split,
  unpin,
  type Workspace,
} from "@/lib/workspace"

const HOME = "home"

/** Shorthand: a workspace built by opening ids into the focused pane. */
function opened(...ids: string[]): Workspace {
  return ids.reduce((workspace, id) => open(workspace, id), newWorkspace(HOME))
}

/** The panes as plain arrays, which is what the assertions are about. */
function panes(workspace: Workspace): string[][] {
  return workspace.groups.map((group) => [...group.openTabs])
}

describe("normalizePinned", () => {
  it("moves pinned tabs to the front, keeping relative order", () => {
    expect(normalizePinned(["a", "b", "c", "d"], new Set(["d", "b"]))).toEqual({
      tabs: ["b", "d", "a", "c"],
      pinnedCount: 2,
    })
  })

  it("ignores pinned ids that are not open", () => {
    // A restore drops tabs whose feature is gone; their pin goes with them.
    expect(normalizePinned(["a", "b"], new Set(["b", "retired-feature"]))).toEqual({
      tabs: ["b", "a"],
      pinnedCount: 1,
    })
  })

  it("keeps the order exactly when nothing is pinned", () => {
    expect(normalizePinned(["a", "b", "c"], new Set())).toEqual({
      tabs: ["a", "b", "c"],
      pinnedCount: 0,
    })
  })
})

describe("clampedTarget", () => {
  const tabs = ["P0", "P1", "U0", "U1"]

  it("will not drop an unpinned tab inside the pinned prefix", () => {
    expect(clampedTarget("U1", "P1", tabs, 2)).toBe("U0")
  })

  it("will not drop a pinned tab past the prefix", () => {
    expect(clampedTarget("P0", "U1", tabs, 2)).toBe("U0")
  })

  it("stops a pinned tab dropped on the strip's dead space at the boundary", () => {
    expect(clampedTarget("P0", null, ["P0", "P1", "U0"], 2)).toBe("U0")
  })

  it("treats the end of the strip as the prefix when everything is pinned", () => {
    expect(clampedTarget("P0", null, ["P0", "P1"], 2)).toBeNull()
  })

  it("leaves a drop within the same region alone", () => {
    expect(clampedTarget("P1", "P0", tabs, 2)).toBe("P0")
    expect(clampedTarget("U0", null, tabs, 2)).toBeNull()
    expect(clampedTarget("U1", "U0", tabs, 2)).toBe("U0")
  })

  it("clamps the first unpinned tab to itself, so it stays put", () => {
    // `moveBefore` no-ops on item === target, which is right: U0 already sits
    // at the boundary.
    expect(clampedTarget("U0", "P0", ["P0", "P1", "U0"], 2)).toBe("U0")
  })

  it("keeps the target for a tab that is not in this pane yet", () => {
    expect(clampedTarget("incoming", "P0", ["P0", "U0"], 1)).toBe("P0")
  })

  it("agrees with where the reorder actually lands", () => {
    // The marker the strip paints and the move the state performs read the
    // same function, so pin the two together: every (tab, target) pair must
    // leave the pinned prefix intact.
    for (const id of tabs) {
      for (const target of [...tabs, null]) {
        const moved = reorderTabs(tabState(tabs, "U0", 2), id, target)
        expect(moved.pinnedCount).toBe(2)
        expect(new Set(moved.openTabs.slice(0, 2))).toEqual(new Set(["P0", "P1"]))
        expect(new Set(moved.openTabs)).toEqual(new Set(tabs))
      }
    }
  })
})

describe("pinning", () => {
  it("moves a pinned tab to the front of its pane", () => {
    const workspace = pin(opened("logcat", "performance"), "performance", HOME)
    expect(panes(workspace)).toEqual([["performance", HOME, "logcat"]])
    expect(pinnedTabs(workspace, 0)).toEqual(["performance"])
    expect(isPinned(workspace, "performance")).toBe(true)
  })

  it("refuses to pin the fallback tab", () => {
    // Home has no chip to mark, so pinning it would only reorder the pane
    // around a tab nobody can see.
    const workspace = pin(opened("logcat"), HOME, HOME)
    expect(pinnedTabs(workspace, 0)).toEqual([])
    expect(panes(workspace)).toEqual([[HOME, "logcat"]])
  })

  it("keeps a pinned tab pinned when it moves to the other pane", () => {
    const start = split(opened("logcat", "performance"), "performance")
    const workspace = move(pin(start, "logcat", HOME), "logcat", 1)
    expect(pinnedTabs(workspace, 1)).toEqual(["logcat"])
    expect(panes(workspace)[1]).toEqual(["logcat", "performance"])
    expect(pinnedTabs(workspace, 0)).toEqual([])
  })

  it("keeps a pinned tab pinned when it splits into a new pane", () => {
    const workspace = split(pin(opened("logcat"), "logcat", HOME), "logcat")
    expect(pinnedTabs(workspace, 1)).toEqual(["logcat"])
  })

  it("spares pinned tabs and Home from Close Other Tabs", () => {
    const workspace = pin(opened("logcat", "performance", "wifi"), "performance", HOME)
    expect(closable(workspace, "logcat", HOME)).toEqual(["wifi"])
    expect(panes(closeOthers(workspace, "logcat", HOME))).toEqual([
      ["performance", HOME, "logcat"],
    ])
  })

  it("lands a drop across the pinned boundary at the boundary", () => {
    const workspace = pin(opened("logcat", "performance", "wifi"), "logcat", HOME)
    const dropped = drop(workspace, "wifi", 0, "logcat")
    // Not ["wifi", "logcat", …] — the pinned tab keeps the front.
    expect(panes(dropped)).toEqual([["logcat", "wifi", HOME, "performance"]])
    expect(pinnedTabs(dropped, 0)).toEqual(["logcat"])
  })

  it("unpins back to the front of the unpinned tabs", () => {
    const pinned = pin(opened("logcat", "performance"), "performance", HOME)
    const workspace = unpin(pinned, "performance")
    expect(pinnedTabs(workspace, 0)).toEqual([])
    expect(panes(workspace)).toEqual([["performance", HOME, "logcat"]])
  })
})

describe("dropLanding and markerSlot", () => {
  const chips = ["a", "b", "c"]

  it("resolves a drop on a chip's far half to the chip after it", () => {
    expect(dropLanding("a", "b", true, chips, 0)).toBe("c")
    // Past the last chip is the end of the strip.
    expect(dropLanding("a", "c", true, chips, 0)).toBeNull()
  })

  it("pulls a drop aimed inside the pinned prefix back to the boundary", () => {
    // "a" pinned: dropping "c" before it lands at "b" instead.
    expect(dropLanding("c", "a", false, chips, 1)).toBe("b")
  })

  it("marks the near edge of the chip the drop lands before", () => {
    expect(markerSlot("c", "b", chips)).toEqual({ id: "b", after: false })
  })

  it("marks the far edge of the last chip for a drop at the end", () => {
    expect(markerSlot("a", null, chips)).toEqual({ id: "c", after: true })
  })

  it("draws nothing when the tab would not move", () => {
    expect(markerSlot("b", "b", chips)).toBeNull()
  })

  it("draws nothing on an empty strip", () => {
    expect(markerSlot("a", null, [])).toBeNull()
  })
})
