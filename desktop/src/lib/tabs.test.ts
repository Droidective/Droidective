import { describe, expect, it } from "vitest"
import {
  activateIndex,
  activateNext,
  activatePrevious,
  closableTabs,
  closeOtherTabs,
  closeTab,
  openTab,
  pinTab,
  pinnedTabs,
  reorderTabs,
  tabState,
  unpinTab,
} from "@/lib/tabs"

// The cases mirror ADBKit's `TabStateTests`: this is a port, and the point of
// porting rather than reinventing is that closing a tab lands focus in the same
// place on both apps.

describe("tabState", () => {
  it("normalises an active tab that is not open", () => {
    expect(tabState(["home", "logcat"], "gone").activeTab).toBe("home")
  })

  it("has no active tab when nothing is open", () => {
    expect(tabState([], "home")).toEqual({ openTabs: [], activeTab: null, pinnedCount: 0 })
  })
})

describe("openTab", () => {
  it("appends and focuses", () => {
    const state = openTab(tabState(["home"], "home"), "logcat")
    expect(state.openTabs).toEqual(["home", "logcat"])
    expect(state.activeTab).toBe("logcat")
  })

  it("refocuses rather than duplicating", () => {
    const state = openTab(tabState(["home", "apps", "logcat"], "logcat"), "apps")
    expect(state.openTabs).toEqual(["home", "apps", "logcat"])
    expect(state.activeTab).toBe("apps")
  })
})

describe("closeTab", () => {
  it("gives focus to the tab that slid into the slot", () => {
    const state = closeTab(tabState(["home", "apps", "logcat"], "apps"), "apps")
    expect(state.openTabs).toEqual(["home", "logcat"])
    expect(state.activeTab).toBe("logcat")
  })

  it("falls back to the new last tab when the rightmost closes", () => {
    expect(closeTab(tabState(["home", "apps", "logcat"], "logcat"), "logcat").activeTab).toBe("apps")
  })

  it("leaves focus alone when closing a background tab", () => {
    const state = closeTab(tabState(["home", "apps", "logcat"], "logcat"), "apps")
    expect(state.openTabs).toEqual(["home", "logcat"])
    expect(state.activeTab).toBe("logcat")
  })

  it("will empty a pane, and leaves what to do about that to the workspace", () => {
    // Deliberately not reseeding here: an emptied pane collapses into its
    // neighbour when there is one, which only `Workspace` can know.
    expect(closeTab(tabState(["logcat"], "logcat"), "logcat")).toEqual({
      openTabs: [],
      activeTab: null,
      pinnedCount: 0,
    })
  })

  it("ignores a tab that is not open", () => {
    const before = tabState(["home"], "home")
    expect(closeTab(before, "logcat")).toBe(before)
  })
})

describe("closeOtherTabs", () => {
  it("keeps the target and the permanent tab", () => {
    const state = closeOtherTabs(tabState(["home", "apps", "logcat"], "home"), "logcat", "home")
    expect(state.openTabs).toEqual(["home", "logcat"])
    expect(state.activeTab).toBe("logcat")
  })
})

describe("cycling", () => {
  it("wraps forwards and backwards", () => {
    const three = tabState(["home", "apps", "logcat"], "logcat")
    expect(activateNext(three).activeTab).toBe("home")
    expect(activatePrevious(tabState(["home", "apps", "logcat"], "home")).activeTab).toBe("logcat")
  })

  it("does nothing with no tabs", () => {
    expect(activateNext(tabState([], null)).activeTab).toBeNull()
  })

  it("jumps to an index, and ignores one out of range", () => {
    const three = tabState(["home", "apps", "logcat"], "home")
    expect(activateIndex(three, 2).activeTab).toBe("logcat")
    expect(activateIndex(three, 9)).toBe(three)
  })
})

describe("reorderTabs", () => {
  it("drops a tab before another", () => {
    const state = reorderTabs(tabState(["home", "apps", "logcat"], "home"), "logcat", "apps")
    expect(state.openTabs).toEqual(["home", "logcat", "apps"])
  })

  it("drops to the end for a null target", () => {
    const state = reorderTabs(tabState(["home", "apps", "logcat"], "home"), "apps", null)
    expect(state.openTabs).toEqual(["home", "logcat", "apps"])
  })

  it("keeps focus on whatever was active", () => {
    const state = reorderTabs(tabState(["home", "apps", "logcat"], "logcat"), "logcat", "apps")
    expect(state.activeTab).toBe("logcat")
  })

  it("ignores a tab that is not open", () => {
    const before = tabState(["home", "apps"], "home")
    expect(reorderTabs(before, "logcat", "apps")).toBe(before)
  })
})

describe("pinning", () => {
  it("moves a pinned tab to the end of the pinned prefix", () => {
    let state = pinTab(tabState(["a", "b", "c"], "a"), "c")
    expect(state.openTabs).toEqual(["c", "a", "b"])
    expect(pinnedTabs(state)).toEqual(["c"])
    state = pinTab(state, "b")
    expect(state.openTabs).toEqual(["c", "b", "a"])
    expect(pinnedTabs(state)).toEqual(["c", "b"])
    // Pinning never changes focus.
    expect(state.activeTab).toBe("a")
  })

  it("does nothing for an already pinned or absent tab", () => {
    const before = tabState(["a", "b"], "a", 1)
    expect(pinTab(before, "a")).toBe(before)
    expect(pinTab(before, "gone")).toBe(before)
  })

  it("drops an unpinned tab to the front of the unpinned tabs", () => {
    const state = unpinTab(tabState(["a", "b", "c"], "c", 2), "a")
    // Back at the boundary, not off to the end of the strip.
    expect(state.openTabs).toEqual(["b", "a", "c"])
    expect(pinnedTabs(state)).toEqual(["b"])
  })

  it("does not put an unpinned tab back where it was before it was pinned", () => {
    // `pinTab` records nothing about where the tab came from, so unpinning
    // lands it at the boundary — where the eye last saw it.
    const pinned = pinTab(tabState(["a", "b", "c", "d"], "b"), "c")
    expect(pinned.openTabs).toEqual(["c", "a", "b", "d"])
    const unpinned = unpinTab(pinned, "c")
    expect(unpinned.openTabs).toEqual(["c", "a", "b", "d"])
    expect(unpinned.pinnedCount).toBe(0)
  })

  it("shrinks the prefix when a pinned tab closes", () => {
    const state = closeTab(tabState(["a", "b", "c"], "c", 2), "a")
    expect(state.openTabs).toEqual(["b", "c"])
    // Not ["b", "c"] — c was never pinned.
    expect(pinnedTabs(state)).toEqual(["b"])
  })

  it("leaves the prefix alone when an unpinned tab closes", () => {
    expect(pinnedTabs(closeTab(tabState(["a", "b", "c"], "c", 2), "c"))).toEqual(["a", "b"])
  })

  it("opens a new tab unpinned", () => {
    const state = openTab(tabState(["a"], "a", 1), "b")
    expect(state.openTabs).toEqual(["a", "b"])
    expect(pinnedTabs(state)).toEqual(["a"])
  })

  it("clamps a persisted count larger than the strip", () => {
    expect(tabState(["a"], "a", 4).pinnedCount).toBe(1)
  })

  it("spares pinned tabs and the permanent tab from a bulk close", () => {
    const state = tabState(["home", "apps", "logcat", "wifi"], "apps")
    const withPin = pinTab(state, "logcat")
    expect(closableTabs(withPin, "apps", "home")).toEqual(["wifi"])
    expect(closeOtherTabs(withPin, "apps", "home").openTabs).toEqual(["logcat", "home", "apps"])
    expect(closeOtherTabs(withPin, "apps", "home").pinnedCount).toBe(1)
  })
})
