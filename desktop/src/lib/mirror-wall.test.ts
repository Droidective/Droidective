/**
 * The wall's maths, against the numbers ADBKit's `MirrorWallTests` asserts.
 *
 * The same values on purpose. This is a port, and a port that agreed only with
 * itself would drift from the Mac's layout one release at a time — which is the
 * difference someone moving between the two notices first.
 */

import { describe, expect, it } from "vitest"

import {
  FULL_QUALITY,
  MAXIMUM_DEVICES,
  autoColumns,
  canAdd,
  manualColumns,
  moved,
  quality,
  reconciled,
  toggled,
} from "@/lib/mirror-wall"

describe("the grid", () => {
  it("gives one tile one column", () => {
    expect(autoColumns(1600, 1)).toBe(1)
    expect(autoColumns(300, 1)).toBe(1)
  })

  it("prefers squarish grids except for three", () => {
    // Phone tiles are portrait, so three across reads better than 2 + 1.
    expect(autoColumns(1600, 2)).toBe(2)
    expect(autoColumns(1600, 3)).toBe(3)
    expect(autoColumns(1600, 4)).toBe(2)
    expect(autoColumns(1600, 5)).toBe(3)
    expect(autoColumns(1600, 6)).toBe(3)
  })

  it("drops columns in a narrow pane instead of shrinking tiles", () => {
    expect(autoColumns(600, 6)).toBe(2)
    expect(autoColumns(300, 6)).toBe(1)
    expect(autoColumns(0, 4)).toBe(1)
  })

  it("survives a pane that has not been measured", () => {
    // A ref's width is NaN before layout, and NaN fails every comparison — so
    // the guard has to let only a real width through.
    expect(autoColumns(Number.NaN, 4)).toBe(1)
    expect(autoColumns(-100, 4)).toBe(1)
  })

  it("lets a manual choice stand in a narrow pane", () => {
    // The user overruling the auto layout is not a mistake to correct.
    expect(manualColumns(3, 6)).toBe(3)
    expect(manualColumns(1, 6)).toBe(1)
  })

  it("never lets a manual choice exceed the tile count", () => {
    expect(manualColumns(3, 2)).toBe(2)
    expect(manualColumns(3, 0)).toBe(1)
    expect(manualColumns(0, 4)).toBe(1)
    expect(manualColumns(-2, 4)).toBe(1)
  })
})

describe("per-tile quality", () => {
  it("makes a one-tile wall look like the full mirror", () => {
    expect(quality(1)).toEqual(FULL_QUALITY)
    expect(FULL_QUALITY.maxSize).toBe(1280)
    expect(FULL_QUALITY.maxFps).toBe(0)
  })

  it("steps down as tiles are added", () => {
    expect(quality(2).maxSize).toBe(1024)
    expect(quality(4).maxSize).toBe(800)
    expect(quality(6).maxSize).toBe(640)
    // Frame rate is capped only once several encoders are running.
    expect(quality(2).maxFps).toBe(0)
    expect(quality(3).maxFps).toBe(30)
    expect(quality(6).maxFps).toBe(24)
  })

  it("never grows past the cap or below one tile", () => {
    expect(quality(7)).toEqual(quality(6))
    expect(quality(0)).toEqual(FULL_QUALITY)
  })
})

describe("selection", () => {
  it("opens on the connected devices when nobody has picked", () => {
    expect(reconciled(null, ["a", "b"])).toEqual(["a", "b"])
  })

  it("stops at the cap when opening on connected devices", () => {
    const connected = ["a", "b", "c", "d", "e", "f", "g", "h"]
    expect(reconciled(null, connected)).toHaveLength(MAXIMUM_DEVICES)
  })

  it("keeps the chosen order and drops devices that left", () => {
    expect(reconciled(["c", "a"], ["a", "b", "c"])).toEqual(["c", "a"])
    expect(reconciled(["c", "a"], ["a", "b"])).toEqual(["a"])
  })

  it("does not refill a selection that was explicitly emptied", () => {
    // Refilling would undo the unchecking that emptied it.
    expect(reconciled([], ["a", "b"])).toEqual([])
    expect(reconciled(["x", "y"], ["a"])).toEqual([])
  })

  it("adds at the end and removes in place", () => {
    expect(toggled("b", ["a"])).toEqual(["a", "b"])
    expect(toggled("a", ["a", "b"])).toEqual(["b"])
  })

  it("refuses to add past the cap rather than evicting a tile", () => {
    const full = ["a", "b", "c", "d", "e", "f"]
    expect(toggled("g", full)).toEqual(full)
    expect(canAdd(full)).toBe(false)
    expect(canAdd(["a"])).toBe(true)
  })
})

describe("reordering by dragging a caption", () => {
  it("moves a tile to its new place", () => {
    expect(moved(["a", "b", "c"], 0, 2)).toEqual(["b", "c", "a"])
    expect(moved(["a", "b", "c"], 2, 0)).toEqual(["c", "a", "b"])
  })

  it("leaves the order alone for a drop that lands nowhere", () => {
    // A no-op beats a reordering nobody asked for.
    const order = ["a", "b", "c"]
    expect(moved(order, 1, 1)).toEqual(order)
    expect(moved(order, -1, 0)).toEqual(order)
    expect(moved(order, 0, 9)).toEqual(order)
  })
})
