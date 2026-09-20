import { describe, expect, it } from "vitest"

import {
  emptySelection,
  extend,
  isEmpty,
  ordered,
  replace,
  retain,
  selectRange,
  toggle,
  type RowSelection,
} from "@/lib/row-selection"

const order = [1, 2, 3, 4, 5]

function picked(selection: RowSelection<number>): number[] {
  return ordered(selection, order)
}

describe("a plain click", () => {
  it("takes the row alone and anchors on it", () => {
    const one = replace(3)
    expect(picked(one)).toEqual([3])
    expect(one.anchor).toBe(3)
  })
})

describe("⌘-click", () => {
  it("adds without disturbing the rest", () => {
    expect(picked(toggle(replace(2), 4))).toEqual([2, 4])
  })

  it("drops a row that was already picked", () => {
    const two = toggle(replace(2), 4)
    expect(picked(toggle(two, 2))).toEqual([4])
  })

  it("moves the anchor either way, so ⌘-then-⇧ spans from what was last touched", () => {
    // The whole point of the anchor moving on a toggle: without it, the next
    // ⇧-click spans from a row nobody touched.
    const dropped = toggle(toggle(replace(2), 4), 4)
    expect(dropped.anchor).toBe(4)
  })
})

describe("⇧-click", () => {
  it("spans from the anchor, in display order, whichever way you click", () => {
    expect(picked(extend(replace(4), 2, order))).toEqual([2, 3, 4])
    expect(picked(extend(replace(2), 4, order))).toEqual([2, 3, 4])
  })

  it("leaves the anchor where it was, so it re-spans instead of ratcheting", () => {
    // Shift down, then shift back up: the second span replaces the first
    // rather than growing from its far end.
    const down = extend(replace(2), 5, order)
    const back = extend(down, 3, order)
    expect(picked(back)).toEqual([2, 3])
    expect(back.anchor).toBe(2)
  })

  it("replaces what was selected unless told to add", () => {
    const scattered = toggle(replace(1), 5)
    expect(picked(extend(scattered, 3, order))).toEqual([3, 4, 5])
    expect(picked(extend(scattered, 3, order, true))).toEqual([1, 3, 4, 5])
  })

  it("is a plain click when the anchor has been trimmed away", () => {
    // A live feed evicts rows; spanning from one that is gone would either
    // throw or select from the top of the buffer.
    const orphan: RowSelection<number> = { ids: new Set([9]), anchor: 9 }
    expect(picked(extend(orphan, 3, order))).toEqual([3])
  })

  it("does nothing for a row the feed does not have", () => {
    const before = replace(2)
    expect(extend(before, 99, order)).toBe(before)
  })
})

describe("a drag", () => {
  it("spans from where the pointer went down", () => {
    expect(picked(selectRange(emptySelection<number>(), 2, 4, order))).toEqual([2, 3, 4])
  })

  it("shrinks again when the pointer comes back", () => {
    // Recomputed from the drag's start every move, so dragging down then back
    // up must not leave the rows behind it selected.
    const wide = selectRange(emptySelection<number>(), 2, 5, order)
    expect(picked(selectRange(wide, 2, 3, order))).toEqual([2, 3])
  })

  it("anchors on the row the drag started from", () => {
    expect(selectRange(emptySelection<number>(), 4, 2, order).anchor).toBe(4)
  })
})

describe("retain", () => {
  it("drops rows the feed no longer shows", () => {
    const wide = selectRange(emptySelection<number>(), 1, 5, order)
    expect(picked(retain(wide, [2, 3]))).toEqual([2, 3])
  })

  it("forgets an anchor that went with them", () => {
    expect(retain(replace(1), [2, 3]).anchor).toBeNull()
  })

  it("keeps an anchor that survived", () => {
    const two = toggle(replace(2), 3)
    expect(retain(two, [2, 3]).anchor).toBe(3)
  })

  it("answers the same value when nothing changed", () => {
    // A feed re-renders constantly; a new object every time would re-render
    // every row with it.
    const two = toggle(replace(2), 3)
    expect(retain(two, order)).toBe(two)
  })
})

describe("ordered", () => {
  it("returns the picks in display order, not the order they were clicked", () => {
    const clicked = toggle(toggle(replace(5), 1), 3)
    expect(ordered(clicked, order)).toEqual([1, 3, 5])
  })

  it("is empty for an empty selection", () => {
    expect(isEmpty(emptySelection())).toBe(true)
    expect(ordered(emptySelection<number>(), order)).toEqual([])
  })
})
