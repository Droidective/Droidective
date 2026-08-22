import { describe, expect, it } from "vitest"
import {
  neighborTab,
  tabLabel,
  withTitle,
  withoutPane,
  type TerminalTab,
} from "@/hooks/useTerminalTabs"
import { paneIds, singlePane, splitPane } from "@/lib/terminal"

/**
 * The tab list's transitions, tested through the pure functions the hook is
 * built from.
 *
 * This app has no DOM test environment, so a hook cannot be rendered here. The
 * answer is not to skip the coverage but to keep the decisions outside the
 * hook — which is where they belong anyway.
 */
function tab(id: string, ordinal: number, title: string | null = null): TerminalTab {
  const pane = `${id}-pane`
  return { id, ordinal, title, tree: singlePane(pane), focused: pane }
}

describe("cycling between terminal tabs", () => {
  const tabs = [tab("a", 1), tab("b", 2), tab("c", 3)]

  it("moves forward and back", () => {
    expect(neighborTab(tabs, "a", 1)).toBe("b")
    expect(neighborTab(tabs, "b", -1)).toBe("a")
  })

  it("wraps in both directions", () => {
    // Going left off the front is the one that breaks: JavaScript's `%` keeps
    // the sign, so a naive index would be -1 and land nowhere.
    expect(neighborTab(tabs, "a", -1)).toBe("c")
    expect(neighborTab(tabs, "c", 1)).toBe("a")
  })

  it("goes nowhere with one tab or none", () => {
    expect(neighborTab([tab("a", 1)], "a", 1)).toBeNull()
    expect(neighborTab([], null, 1)).toBeNull()
  })

  it("goes nowhere from a tab that has closed", () => {
    expect(neighborTab(tabs, "gone", 1)).toBeNull()
  })
})

describe("renaming a tab", () => {
  it("takes the name it was given", () => {
    const renamed = withTitle([tab("a", 1)], "a", "build")
    expect(renamed[0]?.title).toBe("build")
    expect(renamed[0] && tabLabel(renamed[0])).toBe("build")
  })

  it("puts the derived name back when cleared", () => {
    // Blank rather than absent: the field is emptied, and a tab labelled with
    // nothing at all would be unclickable.
    const cleared = withTitle([tab("a", 7, "build")], "a", "   ")
    expect(cleared[0]?.title).toBeNull()
    expect(cleared[0] && tabLabel(cleared[0])).toBe("Shell 7")
  })

  it("trims, so a stray space is not a name", () => {
    expect(withTitle([tab("a", 1)], "a", "  build  ")[0]?.title).toBe("build")
  })

  it("leaves the other tabs alone", () => {
    const renamed = withTitle([tab("a", 1), tab("b", 2)], "a", "build")
    expect(renamed[1]?.title).toBeNull()
  })
})

describe("closing a pane", () => {
  it("keeps the tab while it still has panes", () => {
    const one = tab("a", 1)
    const split = { ...one, tree: splitPane(one.tree, one.focused, "vertical", "second") }
    const after = withoutPane([split], "a", "second")
    expect(after).toHaveLength(1)
    expect(after[0] && paneIds(after[0].tree)).toEqual([one.focused])
  })

  it("takes the tab with its last pane", () => {
    const one = tab("a", 1)
    expect(withoutPane([one, tab("b", 2)], "a", one.focused).map((entry) => entry.id)).toEqual(["b"])
  })

  it("moves focus off the pane that closed", () => {
    const one = tab("a", 1)
    const split = {
      ...one,
      tree: splitPane(one.tree, one.focused, "vertical", "second"),
      focused: "second",
    }
    const after = withoutPane([split], "a", "second")
    expect(after[0]?.focused).toBe(one.focused)
  })

  it("leaves an unknown tab alone", () => {
    const tabs = [tab("a", 1)]
    expect(withoutPane(tabs, "nobody", "whatever")).toEqual(tabs)
  })
})
