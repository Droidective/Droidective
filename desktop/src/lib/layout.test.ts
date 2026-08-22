import { describe, expect, it } from "vitest"
import { emptyLayout, HOME_TAB, loadLayout, restoreWorkspaceFrom, saveLayout } from "@/lib/layout"

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
      favorites: ["logcat"],
      disabledFeatures: ["monkey"],
      hotkeys: { logcat: { code: "KeyL", ctrl: true, alt: true, shift: false, meta: false } },
      runOnAll: true,
      sidebarAutoHide: true,
      zoomStep: 4,
      panes: [
        { tabs: [HOME_TAB, "logcat"], activeTab: "logcat" },
        { tabs: ["apps"], activeTab: "apps" },
      ],
      focusedPane: 1,
      splitFraction: 0.42,
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
      favorites: null,
      disabledFeatures: 42,
      hotkeys: "none",
      runOnAll: "yes",
      sidebarAutoHide: 1,
      // A step from a build with a different number of them.
      zoomStep: 99,
      panes: [{ tabs: [HOME_TAB, 3], activeTab: 9 }, "not a pane", { tabs: [] }],
      focusedPane: "second",
      splitFraction: "half",
    })
    expect(loadLayout(fakeStorage(stored))).toEqual({
      sidebarOrder: ["logcat"],
      categoryOrder: [],
      collapsedCategories: [],
      favorites: [],
      disabledFeatures: [],
      hotkeys: {},
      runOnAll: false,
      sidebarAutoHide: false,
      zoomStep: 7,
      panes: [{ tabs: [HOME_TAB], activeTab: null }],
      focusedPane: 0,
      splitFraction: 0.5,
    })
  })

  it("keeps the whole shortcuts and drops the broken ones", () => {
    // A binding with no key would match a keydown that reported no code.
    const stored = JSON.stringify({
      ...emptyLayout(),
      hotkeys: {
        logcat: { code: "KeyL", ctrl: true },
        keyless: { ctrl: true },
        empty: { code: "" },
        notAnObject: "KeyZ",
      },
    })
    expect(loadLayout(fakeStorage(stored)).hotkeys).toEqual({
      // Absent flags read as false rather than making the entry unusable.
      logcat: { code: "KeyL", ctrl: true, alt: false, shift: false, meta: false },
    })
  })

  it("never restores an empty workspace", () => {
    const stored = JSON.stringify({ ...emptyLayout(), panes: [] })
    expect(loadLayout(fakeStorage(stored)).panes).toEqual(emptyLayout().panes)
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

describe("restoreWorkspaceFrom", () => {
  it("reopens the saved panes, with Home leading the first", () => {
    const workspace = restoreWorkspaceFrom(
      {
        ...emptyLayout(),
        panes: [
          { tabs: ["apps", HOME_TAB], activeTab: "apps" },
          { tabs: ["logcat"], activeTab: "logcat" },
        ],
        focusedPane: 1,
      },
      known,
    )
    expect(workspace.groups.map((group) => [...group.openTabs])).toEqual([
      [HOME_TAB, "apps"],
      ["logcat"],
    ])
    expect(workspace.focusedGroup).toBe(1)
  })

  it("drops a saved tab this build no longer has", () => {
    // A feature that was renamed or removed would otherwise come back as a
    // tab that renders nothing.
    const workspace = restoreWorkspaceFrom(
      { ...emptyLayout(), panes: [{ tabs: [HOME_TAB, "gone", "apps"], activeTab: "gone" }] },
      known,
    )
    expect([...(workspace.groups[0]?.openTabs ?? [])]).toEqual([HOME_TAB, "apps"])
    expect(workspace.groups[0]?.activeTab).toBe(HOME_TAB)
  })

  it("adds Home even when it was not saved", () => {
    const workspace = restoreWorkspaceFrom(
      { ...emptyLayout(), panes: [{ tabs: ["apps"], activeTab: "apps" }] },
      known,
    )
    expect([...(workspace.groups[0]?.openTabs ?? [])]).toEqual([HOME_TAB, "apps"])
    expect(workspace.groups[0]?.activeTab).toBe("apps")
  })
})
