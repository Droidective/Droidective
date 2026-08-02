import { describe, expect, it } from "vitest"
import {
  activeTab,
  activeTabs,
  allOpenTabs,
  close,
  closeOthers,
  drop,
  focus,
  groupIndexOf,
  isSplit,
  move,
  newWorkspace,
  open,
  restoreWorkspace,
  split,
  type Workspace,
} from "@/lib/workspace"

// Mirrors ADBKit's WorkspaceTests: this is a port, and the point of porting is
// that a pane collapses in the same place on both apps.

const HOME = "home"

/** Shorthand: a workspace built by opening ids into the focused pane. */
function opened(...ids: string[]): Workspace {
  return ids.reduce((workspace, id) => open(workspace, id), newWorkspace(HOME))
}

/** The panes as plain arrays, which is what the assertions are about. */
function panes(workspace: Workspace): string[][] {
  return workspace.groups.map((group) => [...group.openTabs])
}

describe("newWorkspace", () => {
  it("starts as one pane showing the fallback", () => {
    const workspace = newWorkspace(HOME)
    expect(panes(workspace)).toEqual([[HOME]])
    expect(activeTab(workspace)).toBe(HOME)
    expect(isSplit(workspace)).toBe(false)
  })
})

describe("open", () => {
  it("lands a new tab in the focused pane", () => {
    expect(panes(opened("apps", "logcat"))).toEqual([[HOME, "apps", "logcat"]])
  })

  it("refocuses a tab in the other pane rather than duplicating it", () => {
    // The invariant that makes moving a tab a move and not a copy.
    const workspace = split(opened("apps", "logcat"), "logcat")
    const back = open(workspace, "logcat")
    expect(panes(back)).toEqual([[HOME, "apps"], ["logcat"]])
    expect(back.focusedGroup).toBe(1)
    expect(allOpenTabs(back).filter((id) => id === "logcat")).toHaveLength(1)
  })
})

describe("split", () => {
  it("moves a tab into a new second pane and focuses it", () => {
    const workspace = split(opened("apps", "logcat"), "logcat")
    expect(panes(workspace)).toEqual([[HOME, "apps"], ["logcat"]])
    expect(workspace.focusedGroup).toBe(1)
    expect(activeTab(workspace)).toBe("logcat")
  })

  it("refuses to leave a pane empty", () => {
    // Splitting the only tab out would leave nothing behind.
    const one = newWorkspace(HOME)
    expect(split(one, HOME)).toBe(one)
  })

  it("refuses a second split", () => {
    const already = split(opened("apps", "logcat"), "logcat")
    expect(split(already, "apps")).toBe(already)
  })

  it("does nothing for a tab that is not open", () => {
    const workspace = opened("apps")
    expect(split(workspace, "nope")).toBe(workspace)
  })
})

describe("close", () => {
  it("collapses an emptied second pane", () => {
    const workspace = split(opened("apps", "logcat"), "logcat")
    const closed = close(workspace, "logcat", HOME)
    expect(panes(closed)).toEqual([[HOME, "apps"]])
    expect(closed.focusedGroup).toBe(0)
  })

  it("never leaves the last pane empty", () => {
    const closed = close(newWorkspace(HOME), HOME, HOME)
    expect(panes(closed)).toEqual([[HOME]])
    expect(activeTab(closed)).toBe(HOME)
  })

  it("leaves the other pane alone", () => {
    const workspace = split(opened("apps", "logcat", "wifi"), "wifi")
    expect(panes(close(workspace, "apps", HOME))).toEqual([[HOME, "logcat"], ["wifi"]])
  })
})

describe("closeOthers", () => {
  it("keeps the target and the permanent tab, in that pane only", () => {
    const workspace = split(opened("apps", "logcat", "wifi"), "wifi")
    expect(panes(closeOthers(workspace, "apps", HOME))).toEqual([[HOME, "apps"], ["wifi"]])
  })
})

describe("move", () => {
  it("moves a tab across and focuses where it landed", () => {
    const workspace = split(opened("apps", "logcat", "wifi"), "wifi")
    const moved = move(workspace, "logcat", 1)
    expect(panes(moved)).toEqual([[HOME, "apps"], ["wifi", "logcat"]])
    expect(moved.focusedGroup).toBe(1)
    expect(activeTab(moved)).toBe("logcat")
  })

  it("collapses the source pane when it empties", () => {
    const workspace = split(opened("apps", "logcat"), "logcat")
    expect(panes(move(workspace, "logcat", 0))).toEqual([[HOME, "apps", "logcat"]])
  })

  it("does nothing for the same pane or a pane that is not there", () => {
    const workspace = opened("apps")
    expect(move(workspace, "apps", 0)).toBe(workspace)
    expect(move(workspace, "apps", 1)).toBe(workspace)
  })
})

describe("drop", () => {
  it("reorders inside a pane", () => {
    const workspace = opened("apps", "logcat")
    expect(panes(drop(workspace, "logcat", 0, "apps"))).toEqual([[HOME, "logcat", "apps"]])
  })

  it("moves across and positions in one go", () => {
    const workspace = split(opened("apps", "logcat", "wifi"), "wifi")
    expect(panes(drop(workspace, "apps", 1, "wifi"))).toEqual([[HOME, "logcat"], ["apps", "wifi"]])
  })
})

describe("focus and reads", () => {
  it("reports both panes' fronts, and highlights the focused one", () => {
    const workspace = split(opened("apps", "logcat"), "logcat")
    expect(activeTabs(workspace).toSorted()).toEqual(["apps", "logcat"])
    expect(activeTab(workspace)).toBe("logcat")
    expect(activeTab(focus(workspace, 0))).toBe("apps")
  })

  it("ignores a focus request for a pane that is not there", () => {
    const workspace = opened("apps")
    expect(focus(workspace, 1)).toBe(workspace)
  })

  it("finds which pane holds a tab", () => {
    const workspace = split(opened("apps", "logcat"), "logcat")
    expect(groupIndexOf(workspace, "apps")).toBe(0)
    expect(groupIndexOf(workspace, "logcat")).toBe(1)
    expect(groupIndexOf(workspace, "nope")).toBe(-1)
  })
})

const known = (id: string) => id !== "gone"

describe("restoreWorkspace", () => {
  it("restores both panes", () => {
    const workspace = restoreWorkspace(
      [
        { tabs: [HOME, "apps"], activeTab: "apps" },
        { tabs: ["logcat"], activeTab: "logcat" },
      ],
      1,
      HOME,
      known,
    )
    expect(panes(workspace)).toEqual([[HOME, "apps"], ["logcat"]])
    expect(workspace.focusedGroup).toBe(1)
  })

  it("drops a tab this build no longer has", () => {
    const workspace = restoreWorkspace([{ tabs: [HOME, "gone"], activeTab: "gone" }], 0, HOME, known)
    expect(panes(workspace)).toEqual([[HOME]])
  })

  it("keeps ids unique across panes", () => {
    // A tab in two panes at once would be two views of one feature fighting
    // over the same id.
    const workspace = restoreWorkspace(
      [
        { tabs: [HOME, "apps"], activeTab: "apps" },
        { tabs: ["apps", "logcat"], activeTab: "apps" },
      ],
      0,
      HOME,
      known,
    )
    expect(panes(workspace)).toEqual([[HOME, "apps"], ["logcat"]])
  })

  it("refuses more than two panes", () => {
    const workspace = restoreWorkspace(
      [
        { tabs: ["a"], activeTab: "a" },
        { tabs: ["b"], activeTab: "b" },
        { tabs: ["c"], activeTab: "c" },
      ],
      0,
      HOME,
      known,
    )
    expect(workspace.groups).toHaveLength(2)
  })

  it("falls back for an empty or all-invalid restore", () => {
    expect(panes(restoreWorkspace([], 0, HOME, known))).toEqual([[HOME]])
    expect(panes(restoreWorkspace([{ tabs: ["gone"], activeTab: null }], 0, HOME, known))).toEqual([
      [HOME],
    ])
  })

  it("clamps a focus index that is out of range", () => {
    const workspace = restoreWorkspace([{ tabs: [HOME], activeTab: HOME }], 7, HOME, known)
    expect(workspace.focusedGroup).toBe(0)
  })
})
