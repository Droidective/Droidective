import { describe, expect, it } from "vitest"
import { handlePoints, hitTest, rotationHandle } from "@/lib/screenshot-handles"
import { annotation, type Annotation, type MarkupTool, type Size } from "@/lib/screenshot-markup"

const DISPLAY: Size = { width: 400, height: 800 }

/** A stand-in for canvas text measurement: 0.6em per character, 1.2em tall. */
const measure = (text: string, fontSize: number) => ({
  width: text.length * fontSize * 0.6,
  height: fontSize * 1.2,
})

function pen(points: { x: number; y: number }[]): Annotation {
  return annotation({ tool: "pen", points } as Partial<Annotation> & { tool: MarkupTool })
}

function shape(tool: MarkupTool, a: { x: number; y: number }, b: { x: number; y: number }): Annotation {
  return annotation({ tool, points: [a, b] } as Partial<Annotation> & { tool: MarkupTool })
}

describe("handlePoints", () => {
  it("gives a two-point shape its two endpoints", () => {
    const pts = handlePoints(shape("arrow", { x: 0.1, y: 0.2 }, { x: 0.7, y: 0.8 }), DISPLAY)
    expect(pts).toEqual([{ x: 0.1, y: 0.2 }, { x: 0.7, y: 0.8 }])
  })

  it("gives a freehand stroke four corners", () => {
    expect(handlePoints(pen([{ x: 0.1, y: 0.1 }, { x: 0.5, y: 0.5 }]), DISPLAY)).toHaveLength(4)
  })

  it("gives text one corner", () => {
    const text = annotation({ tool: "text", points: [{ x: 0.1, y: 0.1 }], text: "abc" })
    expect(handlePoints(text, DISPLAY, measure)).toHaveLength(1)
  })

  it("has none for a shape with no points", () => {
    expect(handlePoints(annotation({ tool: "line", points: [] }), DISPLAY)).toEqual([])
  })

  it("carries the handles around with a rotation", () => {
    const flat = shape("line", { x: 0.2, y: 0.5 }, { x: 0.8, y: 0.5 })
    const turned = { ...flat, rotation: Math.PI }
    const [first] = handlePoints(turned, DISPLAY)
    // A half-turn swaps the ends of a line through its own centre.
    expect(first?.x).toBeCloseTo(0.8, 6)
  })
})

describe("rotationHandle", () => {
  it("sits above the shape", () => {
    const box = shape("rectangle", { x: 0.4, y: 0.4 }, { x: 0.6, y: 0.6 })
    const handle = rotationHandle(box, DISPLAY)
    expect(handle).not.toBeNull()
    expect(handle?.y).toBeLessThan(0.4)
    expect(handle?.x).toBeCloseTo(0.5, 6)
  })

  it("has none for an empty annotation", () => {
    expect(rotationHandle(annotation({ tool: "rectangle", points: [] }), DISPLAY)).toBeNull()
  })
})

describe("hitTest", () => {
  it("picks an area shape from inside it", () => {
    const box = shape("rectangle", { x: 0.2, y: 0.2 }, { x: 0.6, y: 0.6 })
    expect(hitTest([box], { x: 0.4 * 400, y: 0.4 * 800 }, DISPLAY, 6)).toBe(0)
  })

  it("misses an area shape from well outside it", () => {
    const box = shape("rectangle", { x: 0.2, y: 0.2 }, { x: 0.6, y: 0.6 })
    expect(hitTest([box], { x: 0.9 * 400, y: 0.9 * 800 }, DISPLAY, 6)).toBeNull()
  })

  it("picks a stroke near its path, not merely inside its box", () => {
    // A diagonal: the top-right of its bounding box is empty space.
    const stroke = pen([{ x: 0.2, y: 0.2 }, { x: 0.6, y: 0.6 }])
    expect(hitTest([stroke], { x: 0.4 * 400, y: 0.4 * 800 }, DISPLAY, 8)).toBe(0)
    expect(hitTest([stroke], { x: 0.6 * 400, y: 0.2 * 800 }, DISPLAY, 8)).toBeNull()
  })

  it("prefers the newest of two overlapping shapes", () => {
    const under = shape("rectangle", { x: 0.1, y: 0.1 }, { x: 0.9, y: 0.9 })
    const over = shape("rectangle", { x: 0.3, y: 0.3 }, { x: 0.5, y: 0.5 })
    expect(hitTest([under, over], { x: 0.4 * 400, y: 0.4 * 800 }, DISPLAY, 6)).toBe(1)
  })

  it("honours the tolerance around a thin shape", () => {
    const line = shape("line", { x: 0.2, y: 0.5 }, { x: 0.8, y: 0.5 })
    const justOff = { x: 0.5 * 400, y: 0.5 * 800 + 5 }
    expect(hitTest([line], justOff, DISPLAY, 8)).toBe(0)
    expect(hitTest([line], justOff, DISPLAY, 2)).toBeNull()
  })

  it("tests a rotated shape in its own frame", () => {
    // A tall thin box turned a quarter-turn is wide and short: a point beside
    // it is inside the rotated shape and outside the upright one.
    const tall = shape("rectangle", { x: 0.45, y: 0.2 }, { x: 0.55, y: 0.8 })
    const turned = { ...tall, rotation: Math.PI / 2 }
    const beside = { x: 0.5 * 400, y: 0.5 * 800 }
    expect(hitTest([turned], beside, DISPLAY, 4)).toBe(0)
  })

  it("finds nothing in an empty list", () => {
    expect(hitTest([], { x: 1, y: 1 }, DISPLAY, 6)).toBeNull()
  })
})
