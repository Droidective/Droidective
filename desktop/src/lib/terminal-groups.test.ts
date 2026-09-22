import { describe, expect, it } from "vitest"

import {
  addTab,
  allTabIds,
  DEFAULT_GROUP_NAME,
  emptyEntries,
  entryId,
  groupOfTab,
  moveGroupBefore,
  moveGroupToEnd,
  moveTabBefore,
  moveTabToEnd,
  moveTabToGroup,
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

describe("moving a tab", () => {
  const grouped = newGroup([{ kind: "tab", id: "a" }, { kind: "tab", id: "b" }], "b", "Work", "g1")

  it("the destination follows the target: before a loose tab it lands loose", () => {
    const start: Entry[] = [{ kind: "tab", id: "a" }, { kind: "tab", id: "b" }]
    expect(moveTabBefore(start, "b", "a")).toEqual([
      { kind: "tab", id: "b" },
      { kind: "tab", id: "a" },
    ])
  })

  it("…and before a grouped tab it joins that group", () => {
    // The one rule here worth a test: a second "which group?" decision at the
    // call site would disagree with this the first time a group was dragged.
    const moved = moveTabBefore(grouped, "a", "b")
    expect(groupOfTab(moved, "a")?.id).toBe("g1")
    expect(allTabIds(moved)).toEqual(["a", "b"])
  })

  it("leaves a group it emptied behind", () => {
    const moved = moveTabBefore(grouped, "b", "a")
    expect(moved.some((entry) => entry.kind === "group")).toBe(false)
    expect(allTabIds(moved)).toEqual(["b", "a"])
  })

  it("does nothing for an unknown id, or for a tab dropped on itself", () => {
    const start: Entry[] = [{ kind: "tab", id: "a" }]
    expect(moveTabBefore(start, "a", "a")).toEqual(start)
    expect(moveTabBefore(start, "a", "zz")).toEqual(start)
    expect(moveTabBefore(start, "zz", "a")).toEqual(start)
  })

  it("drops onto a group's header by joining the end of it", () => {
    const start = [...grouped, { kind: "tab" as const, id: "c" }]
    expect(allTabIds(moveTabToGroup(start, "c", "g1"))).toEqual(["a", "b", "c"])
  })

  it("does not churn a group whose only tab is the one being dropped on it", () => {
    expect(moveTabToGroup(grouped, "b", "g1")).toEqual(grouped)
  })

  it("moves out of a group to the strip's end", () => {
    const moved = moveTabToEnd(grouped, "b")
    expect(groupOfTab(moved, "b")).toBeNull()
    expect(allTabIds(moved)).toEqual(["a", "b"])
  })

  it("leaves a tab that is already last alone", () => {
    const start: Entry[] = [{ kind: "tab", id: "a" }, { kind: "tab", id: "b" }]
    expect(moveTabToEnd(start, "b")).toEqual(start)
  })
})

describe("moving a group", () => {
  const start = newGroup(
    [{ kind: "tab", id: "a" }, { kind: "tab", id: "b" }, { kind: "tab", id: "c" }],
    "b",
    "Work",
    "g1",
  )

  it("moves before another top-level entry, group or loose tab", () => {
    expect(moveGroupBefore(start, "g1", "a").map((entry) => entryId(entry))).toEqual(["g1", "a", "c"])
  })

  it("takes its tabs with it", () => {
    expect(allTabIds(moveGroupBefore(start, "g1", "a"))).toEqual(["b", "a", "c"])
  })

  it("moves to the end", () => {
    expect(moveGroupToEnd(start, "g1").map((entry) => entryId(entry))).toEqual(["a", "c", "g1"])
  })

  it("stays put for a target that is inside a group rather than a top-level row", () => {
    // Sending it to one end instead would move a group nobody dragged there.
    expect(moveGroupBefore(start, "g1", "b")).toEqual(start)
  })

  it("does nothing for an unknown group", () => {
    expect(moveGroupBefore(start, "zz", "a")).toEqual(start)
    expect(moveGroupToEnd(start, "zz")).toEqual(start)
  })
})
