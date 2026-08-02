import { describe, expect, it } from "vitest"
import { emptyLayout, HOME_TAB, loadLayout, restoreTabs, saveLayout } from "@/lib/layout"

/** Enough of `Storage` for the two calls the layout makes. */
function fakeStorage(initial: string | null = null) {
  let value = initial
  return {
    getItem: () => value,
    setItem: (_key: string, next: string) => {
      value = next
    },
    read: () => value,
  }
}

describe("loadLayout", () => {
  it("returns the default when nothing is saved", () => {
    expect(loadLayout(fakeStorage())).toEqual(emptyLayout())
  })

  it("round-trips what was saved", () => {
    const storage = fakeStorage()
    const layout = {
      sidebarOrder: ["logcat", "apps"],
      categoryOrder: ["logs"],
      collapsedCategories: ["input"],
      openTabs: [HOME_TAB, "logcat"],
      activeTab: "logcat",
    }
    saveLayout(storage, layout)
    expect(loadLayout(storage)).toEqual(layout)
  })

  it("falls back rather than throwing on unparseable JSON", () => {
    expect(loadLayout(fakeStorage("{not json"))).toEqual(emptyLayout())
  })

  it("falls back for a value that is not an object", () => {
    expect(loadLayout(fakeStorage("42"))).toEqual(emptyLayout())
    expect(loadLayout(fakeStorage("null"))).toEqual(emptyLayout())
  })

  it("drops entries of the wrong type instead of trusting them", () => {
    const stored = JSON.stringify({
      sidebarOrder: ["logcat", 7, null],
      categoryOrder: "logs",
      collapsedCategories: [{ nope: true }],
      openTabs: [HOME_TAB],
      activeTab: 3,
    })
    expect(loadLayout(fakeStorage(stored))).toEqual({
      sidebarOrder: ["logcat"],
      categoryOrder: [],
      collapsedCategories: [],
      openTabs: [HOME_TAB],
      activeTab: null,
    })
  })

  it("never restores an empty tab strip", () => {
    const stored = JSON.stringify({ ...emptyLayout(), openTabs: [] })
    expect(loadLayout(fakeStorage(stored)).openTabs).toEqual([HOME_TAB])
  })
})

describe("saveLayout", () => {
  it("swallows a storage that refuses to write", () => {
    const refusing = {
      setItem: () => {
        throw new Error("QuotaExceededError")
      },
    }
    expect(() => {
      saveLayout(refusing, emptyLayout())
    }).not.toThrow()
  })
})

const known = (id: string) => id === "logcat" || id === "apps"

describe("restoreTabs", () => {
  it("reopens the saved tabs, with Home leading", () => {
    const state = restoreTabs(
      { ...emptyLayout(), openTabs: ["apps", HOME_TAB, "logcat"], activeTab: "logcat" },
      known,
    )
    expect(state.openTabs).toEqual([HOME_TAB, "apps", "logcat"])
    expect(state.activeTab).toBe("logcat")
  })

  it("drops a saved tab this build no longer has", () => {
    // A feature that was renamed or removed would otherwise come back as a tab
    // that renders nothing.
    const state = restoreTabs(
      { ...emptyLayout(), openTabs: [HOME_TAB, "gone", "apps"], activeTab: "gone" },
      known,
    )
    expect(state.openTabs).toEqual([HOME_TAB, "apps"])
    expect(state.activeTab).toBe(HOME_TAB)
  })

  it("adds Home even when it was not saved", () => {
    const state = restoreTabs({ ...emptyLayout(), openTabs: ["apps"], activeTab: "apps" }, known)
    expect(state.openTabs).toEqual([HOME_TAB, "apps"])
    expect(state.activeTab).toBe("apps")
  })
})
