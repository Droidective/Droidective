import { describe, expect, it } from "vitest"

import {
  addTab,
  allTabIds,
  DEFAULT_GROUP_NAME,
  emptyEntries,
  groupOfTab,
  newGroup,
  removeGroup,
  removeTab,
  renameGroup,
  setCollapsed,
  type Entry,
} from "@/lib/terminal-groups"

function rail(): Entry[] {
  return addTab(addTab(addTab(emptyEntries(), "a"), "b"), "c")
}

describe("adding", () => {
  it("appends loose by default, so a fresh rail has no groups", () => {
    expect(allTabIds(rail())).toEqual(["a", "b", "c"])
    expect(rail().every((entry) => entry.kind === "tab")).toBe(true)
  })

  it("appends into a group when one is named", () => {
    const grouped = newGroup(rail(), "a", "Build", "g1")
    expect(allTabIds(addTab(grouped, "d", "g1"))).toEqual(["a", "d", "b", "c"])
  })

  it("falls back to loose when the group has gone", () => {
    // Dropping the tab instead would leave a shell running with nothing on
    // screen to close it from.
    expect(allTabIds(addTab(rail(), "d", "nope"))).toEqual(["a", "b", "c", "d"])
  })
})

describe("grouping", () => {
  it("turns a loose tab into a group in place, so the rail does not reorder", () => {
    const grouped = newGroup(rail(), "b", "Build", "g1")
    expect(allTabIds(grouped)).toEqual(["a", "b", "c"])
    expect(groupOfTab(grouped, "b")?.name).toBe("Build")
  })

  it("names an unnamed group rather than leaving it blank", () => {
    expect(groupOfTab(newGroup(rail(), "a", "   ", "g1"), "a")?.name).toBe(DEFAULT_GROUP_NAME)
  })

  it("detaches a tab that is already grouped — it cannot be in two", () => {
    const first = newGroup(rail(), "a", "Build", "g1")
    const second = newGroup(first, "a", "Test", "g2")
    expect(groupOfTab(second, "a")?.name).toBe("Test")
    expect(second.filter((entry) => entry.kind === "group")).toHaveLength(1)
  })

  it("does nothing for a tab the rail does not have", () => {
    expect(allTabIds(newGroup(rail(), "zz", "Build", "g1"))).toEqual(["a", "b", "c"])
  })
})

describe("renaming and collapsing", () => {
  it("ignores an empty rename rather than blanking the header", () => {
    const grouped = newGroup(rail(), "a", "Build", "g1")
    expect(groupOfTab(renameGroup(grouped, "g1", "  "), "a")?.name).toBe("Build")
  })

  it("collapses and expands", () => {
    const grouped = newGroup(rail(), "a", "Build", "g1")
    expect(groupOfTab(setCollapsed(grouped, "g1", true), "a")?.collapsed).toBe(true)
  })
})

describe("removing", () => {
  it("hands back the tabs a closed group held, in order", () => {
    // The caller owns the shells; dropping these would leave ptys running.
    let entries = newGroup(rail(), "a", "Build", "g1")
    entries = addTab(entries, "d", "g1")
    const { entries: left, closed } = removeGroup(entries, "g1")
    expect(closed).toEqual(["a", "d"])
    expect(allTabIds(left)).toEqual(["b", "c"])
  })

  it("deletes a group its last tab left, rather than leaving an empty header", () => {
    const grouped = newGroup(rail(), "a", "Build", "g1")
    const left = removeTab(grouped, "a")
    expect(left.some((entry) => entry.kind === "group")).toBe(false)
    expect(allTabIds(left)).toEqual(["b", "c"])
  })

  it("keeps a group that still has tabs", () => {
    let entries = newGroup(rail(), "a", "Build", "g1")
    entries = addTab(entries, "d", "g1")
    expect(allTabIds(removeTab(entries, "a"))).toEqual(["d", "b", "c"])
  })

  it("returns nothing for a group that is not there", () => {
    expect(removeGroup(rail(), "nope").closed).toEqual([])
  })
})
