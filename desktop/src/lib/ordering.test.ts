import { describe, expect, it } from "vitest"
import { applyDrop, dropTarget, moveBefore, moveToEnd, rankBy } from "@/lib/ordering"

describe("moveBefore", () => {
  it("moves forwards and backwards", () => {
    expect(moveBefore("a", "c", ["a", "b", "c"])).toEqual(["b", "a", "c"])
    expect(moveBefore("c", "a", ["a", "b", "c"])).toEqual(["c", "a", "b"])
  })

  it("does nothing when the item is the target or is absent", () => {
    expect(moveBefore("a", "a", ["a", "b"])).toEqual(["a", "b"])
    expect(moveBefore("z", "a", ["a", "b"])).toEqual(["a", "b"])
  })

  it("appends when the target is absent", () => {
    expect(moveBefore("a", "z", ["a", "b"])).toEqual(["b", "a"])
  })

  it("does not mutate its input", () => {
    const order = ["a", "b", "c"]
    moveBefore("c", "a", order)
    expect(order).toEqual(["a", "b", "c"])
  })
})

describe("moveToEnd", () => {
  it("moves an item to the end", () => {
    expect(moveToEnd("a", ["a", "b", "c"])).toEqual(["b", "c", "a"])
  })

  it("does nothing for an absent item", () => {
    expect(moveToEnd("z", ["a", "b"])).toEqual(["a", "b"])
  })
})

describe("dropTarget", () => {
  const order = ["a", "b", "c"]

  it("drops before the row it landed on", () => {
    expect(dropTarget("b", false, order)).toBe("b")
  })

  it("drops past a row by aiming at the next one", () => {
    expect(dropTarget("b", true, order)).toBe("c")
  })

  it("reaches the end past the last row", () => {
    // Without this the last slot is unreachable: there is no row to drop
    // before.
    expect(dropTarget("c", true, order)).toBeNull()
  })

  it("treats an unknown target as the end", () => {
    expect(dropTarget("z", true, order)).toBeNull()
  })
})

describe("applyDrop", () => {
  // One sidebar group inside a global order that also holds other groups.
  const group = ["b", "c", "d"]
  const full = ["a", "b", "c", "d", "e"]

  it("moves a row up inside its group", () => {
    expect(applyDrop("d", "b", false, group, full)).toEqual(["a", "d", "b", "c", "e"])
  })

  it("moves a row down inside its group", () => {
    expect(applyDrop("b", "c", true, group, full)).toEqual(["a", "c", "b", "d", "e"])
  })

  it("lands past the last row of the group, not the end of everything", () => {
    // "e" belongs to another group and must not be jumped over.
    expect(applyDrop("b", "d", true, group, full)).toEqual(["a", "c", "d", "b", "e"])
  })

  it("appends when the group runs to the end of the order", () => {
    expect(applyDrop("c", "e", true, ["c", "d", "e"], full)).toEqual(["a", "b", "d", "e", "c"])
  })

  it("treats dropping the last row past itself as no move", () => {
    expect(applyDrop("d", "d", true, group, full)).toBeNull()
  })

  it("does nothing when the group holds only the row being dragged", () => {
    expect(applyDrop("b", "b", true, ["b"], full)).toBeNull()
  })

  it("reports a drop that changes nothing", () => {
    // Onto itself, and onto the gap it already occupies — both are the drags
    // people make by accident, and neither should write an order.
    expect(applyDrop("c", "c", false, group, full)).toBeNull()
    expect(applyDrop("c", "b", true, group, full)).toBeNull()
    expect(applyDrop("c", "d", false, group, full)).toBeNull()
  })
})

const identify = (item: string) => item

describe("rankBy", () => {
  it("puts ranked items first, in rank order", () => {
    expect(rankBy(["a", "b", "c"], ["c", "b"], identify)).toEqual(["c", "b", "a"])
  })

  it("keeps unranked items in their incoming order", () => {
    // The registry order is the tiebreak, so an item nobody has dragged never
    // moves relative to its neighbours.
    expect(rankBy(["a", "b", "c", "d"], ["d"], identify)).toEqual(["d", "a", "b", "c"])
  })

  it("ignores ids that are not present", () => {
    expect(rankBy(["a", "b"], ["z", "b"], identify)).toEqual(["b", "a"])
  })

  it("honours the first position a duplicated id was given", () => {
    expect(rankBy(["a", "b", "c"], ["c", "a", "c"], identify)).toEqual(["c", "a", "b"])
  })

  it("does not mutate its input", () => {
    const items = ["a", "b", "c"]
    rankBy(items, ["c"], identify)
    expect(items).toEqual(["a", "b", "c"])
  })
})
