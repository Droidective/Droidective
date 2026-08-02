import { describe, expect, it } from "vitest"
import {
  activateIndex,
  activateNext,
  activatePrevious,
  closeOtherTabs,
  closeTab,
  openTab,
  reorderTabs,
  tabState,
} from "@/lib/tabs"

// The cases mirror ADBKit's `TabStateTests`: this is a port, and the point of
// porting rather than reinventing is that closing a tab lands focus in the same
// place on both apps.

describe("tabState", () => {
  it("normalises an active tab that is not open", () => {
    expect(tabState(["home", "logcat"], "gone").activeTab).toBe("home")
  })

  it("has no active tab when nothing is open", () => {
    expect(tabState([], "home")).toEqual({ openTabs: [], activeTab: null })
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
    const state = closeTab(tabState(["home", "apps", "logcat"], "apps"), "apps", "home")
    expect(state.openTabs).toEqual(["home", "logcat"])
    expect(state.activeTab).toBe("logcat")
  })

  it("falls back to the new last tab when the rightmost closes", () => {
    const state = closeTab(tabState(["home", "apps", "logcat"], "logcat"), "logcat", "home")
    expect(state.activeTab).toBe("apps")
  })

  it("leaves focus alone when closing a background tab", () => {
    const state = closeTab(tabState(["home", "apps", "logcat"], "logcat"), "apps", "home")
    expect(state.openTabs).toEqual(["home", "logcat"])
    expect(state.activeTab).toBe("logcat")
  })

  it("reseeds the fallback rather than leaving an empty window", () => {
    expect(closeTab(tabState(["logcat"], "logcat"), "logcat", "home")).toEqual({
      openTabs: ["home"],
      activeTab: "home",
    })
  })

  it("ignores a tab that is not open", () => {
    const before = tabState(["home"], "home")
    expect(closeTab(before, "logcat", "home")).toBe(before)
  })
})

describe("closeOtherTabs", () => {
  it("keeps the target and the permanent fallback", () => {
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
