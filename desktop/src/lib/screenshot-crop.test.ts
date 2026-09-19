import { describe, expect, it } from "vitest"
import {
  clampCrop,
  cropGrab,
  cropHandles,
  cropRotationHandle,
  MIN_CROP,
  moveCrop,
  resizeCrop,
  rotateCrop,
} from "@/lib/screenshot-crop"
import type { Rect, Size } from "@/lib/screenshot-markup"

const SIZE: Size = { width: 400, height: 800 }
const BOX: Rect = { x: 0.25, y: 0.25, width: 0.5, height: 0.5 }

describe("cropHandles", () => {
  it("gives the four corners in a stable order", () => {
    expect(cropHandles(BOX, 0, SIZE)).toEqual([
      { x: 0.25, y: 0.25 },
      { x: 0.75, y: 0.25 },
      { x: 0.75, y: 0.75 },
      { x: 0.25, y: 0.75 },
    ])
  })

  it("carries them around a rotation", () => {
    const [first] = cropHandles(BOX, Math.PI, SIZE)
    // A half-turn about the centre puts the top-left where the bottom-right was.
    expect(first?.x).toBeCloseTo(0.75, 6)
    expect(first?.y).toBeCloseTo(0.75, 6)
  })
})

describe("cropRotationHandle", () => {
  it("floats above the top edge", () => {
    const handle = cropRotationHandle(BOX, 0, SIZE)
    expect(handle.x).toBeCloseTo(0.5, 6)
    expect(handle.y).toBeLessThan(0.25)
  })
})

describe("cropGrab", () => {
  it("takes a corner before the box it sits on", () => {
    // The corner is inside the box's own area, so an order that tested the box
    // first would make a large crop impossible to resize.
    const grab = cropGrab({ x: 0.25 * 400, y: 0.25 * 800 }, BOX, 0, SIZE, 8)
    expect(grab).toEqual({ kind: "corner", index: 0 })
  })

  it("takes the rotation handle before anything else", () => {
    const at = cropRotationHandle(BOX, 0, SIZE)
    expect(cropGrab({ x: at.x * 400, y: at.y * 800 }, BOX, 0, SIZE, 8)).toEqual({ kind: "rotate" })
  })

  it("moves from inside the box", () => {
    expect(cropGrab({ x: 0.5 * 400, y: 0.5 * 800 }, BOX, 0, SIZE, 8)).toEqual({ kind: "move" })
  })

  it("takes nothing from outside it", () => {
    expect(cropGrab({ x: 0.05 * 400, y: 0.05 * 800 }, BOX, 0, SIZE, 8)).toEqual({ kind: "none" })
  })

  it("tests the box in its own frame when it is turned", () => {
    const tall: Rect = { x: 0.45, y: 0.1, width: 0.1, height: 0.8 }
    const turned = Math.PI / 2
    // Turned a quarter, the tall box is wide: a point out to the side is inside
    // it, and would be outside the upright one.
    expect(cropGrab({ x: 0.2 * 400, y: 0.5 * 800 }, tall, turned, SIZE, 6).kind).toBe("move")
  })
})

describe("clampCrop", () => {
  it("keeps the box inside the image", () => {
    const clamped = clampCrop({ x: 0.9, y: 0.9, width: 0.4, height: 0.4 })
    expect(clamped.x + clamped.width).toBeLessThanOrEqual(1.0000001)
    expect(clamped.y + clamped.height).toBeLessThanOrEqual(1.0000001)
  })

  it("refuses a box too small to be meant", () => {
    const clamped = clampCrop({ x: 0.5, y: 0.5, width: 0.0001, height: 0.0001 })
    expect(clamped.width).toBe(MIN_CROP)
    expect(clamped.height).toBe(MIN_CROP)
  })

  it("pulls a negative origin back to the edge", () => {
    expect(clampCrop({ x: -0.2, y: -0.3, width: 0.4, height: 0.4 })).toMatchObject({ x: 0, y: 0 })
  })
})

describe("moveCrop", () => {
  it("translates the box", () => {
    expect(moveCrop(BOX, { x: 0.1, y: -0.1 })).toMatchObject({ x: 0.35, y: 0.15 })
  })

  it("stops at the edge rather than leaving the image", () => {
    const moved = moveCrop(BOX, { x: 0.9, y: 0 })
    expect(moved.x + moved.width).toBeCloseTo(1, 6)
    expect(moved.width).toBeCloseTo(BOX.width, 6)
  })
})

describe("resizeCrop", () => {
  it("anchors the opposite corner", () => {
    const resized = resizeCrop(BOX, 0, { x: 0.5, y: 0.5 }, 0, SIZE)
    // Dragging the top-left inward leaves the bottom-right where it was.
    expect(resized.x + resized.width).toBeCloseTo(0.75, 6)
    expect(resized.y + resized.height).toBeCloseTo(0.75, 6)
    expect(resized.width).toBeCloseTo(0.25, 6)
  })

  it("survives a drag past the anchor without inverting", () => {
    const resized = resizeCrop(BOX, 0, { x: 0.95, y: 0.95 }, 0, SIZE)
    expect(resized.width).toBeGreaterThan(0)
    expect(resized.height).toBeGreaterThan(0)
    expect(resized.x).toBeCloseTo(0.75, 6)
  })

  it("clamps a drag outside the image", () => {
    const resized = resizeCrop(BOX, 2, { x: 1.9, y: 1.9 }, 0, SIZE)
    expect(resized.x + resized.width).toBeLessThanOrEqual(1.0000001)
  })

  it("ignores a corner index the box does not have", () => {
    expect(resizeCrop(BOX, 9, { x: 0.5, y: 0.5 }, 0, SIZE)).toEqual(BOX)
  })
})

describe("rotateCrop", () => {
  it("is zero with the cursor straight above the centre", () => {
    expect(Math.abs(rotateCrop(BOX, { x: 0.5, y: 0.1 }, SIZE))).toBeCloseTo(0, 6)
  })

  it("is a quarter-turn with the cursor to the right", () => {
    expect(rotateCrop(BOX, { x: 0.9, y: 0.5 }, SIZE)).toBeCloseTo(Math.PI / 2, 6)
  })
})
