import { describe, expect, it } from "vitest"
import { moved, resizing, rotated } from "@/lib/screenshot-handles"
import {
  annotation,
  blurRegions,
  boundingBox,
  bounds,
  isDragShape,
  MARKUP_TOOLS,
  rotate,
  rectBetween,
  TOOL_LABELS,
  type Annotation,
  type MarkupTool,
  type Size,
} from "@/lib/screenshot-markup"

const DISPLAY: Size = { width: 400, height: 800 }

/** A stand-in for canvas text measurement: 10px wide per character, 1.2em tall. */
const measure = (text: string, fontSize: number) => ({
  width: text.length * fontSize * 0.6,
  height: fontSize * 1.2,
})

function pen(points: { x: number; y: number }[]): Annotation {
  return annotation({ tool: "pen", points, id: "pen" } as Partial<Annotation> & { tool: MarkupTool })
}

function shape(tool: MarkupTool, a: { x: number; y: number }, b: { x: number; y: number }): Annotation {
  return annotation({ tool, points: [a, b] } as Partial<Annotation> & { tool: MarkupTool })
}

describe("the tool table", () => {
  it("labels every tool", () => {
    for (const tool of MARKUP_TOOLS) {
      expect(TOOL_LABELS[tool]).toBeTruthy()
    }
  })

  it("marks exactly the two-point tools as drag shapes", () => {
    const drags = MARKUP_TOOLS.filter((tool) => isDragShape(tool))
    expect(drags).toEqual(["arrow", "line", "rectangle", "ellipse", "redact"])
  })
})

describe("boundingBox", () => {
  it("wraps every point of a freehand stroke", () => {
    const box = boundingBox(pen([{ x: 0.2, y: 0.4 }, { x: 0.5, y: 0.1 }, { x: 0.3, y: 0.6 }]))
    expect(box).toEqual({ x: 0.2, y: 0.1, width: 0.3, height: 0.5 })
  })

  it("is empty for an annotation with no points", () => {
    expect(boundingBox(pen([]))).toEqual({ x: 0, y: 0, width: 0, height: 0 })
  })

  it("gives text an approximate extent so it is still selectable unmeasured", () => {
    const text = annotation({ tool: "text", points: [{ x: 0.1, y: 0.1 }], text: "hello" })
    const box = boundingBox(text)
    expect(box.width).toBeGreaterThan(0)
    expect(box.height).toBeGreaterThan(0)
  })
})

describe("bounds", () => {
  it("measures text with its real font when a measurer is given", () => {
    const text = annotation({ tool: "text", points: [{ x: 0, y: 0 }], text: "abcd", width: 6 })
    const measured = bounds(text, DISPLAY, measure)
    // 400 * 0.03 * 1 = 12px font, four characters at 0.6em = 28.8px wide.
    expect(measured.width).toBeCloseTo(28.8 / 400, 5)
  })

  it("falls back to the approximation with no measurer", () => {
    const text = annotation({ tool: "text", points: [{ x: 0, y: 0 }], text: "abcd" })
    expect(bounds(text, DISPLAY)).toEqual(boundingBox(text))
  })

  it("measures an empty label as the placeholder it draws", () => {
    const empty = annotation({ tool: "text", points: [{ x: 0, y: 0 }], text: "" })
    const filled = annotation({ tool: "text", points: [{ x: 0, y: 0 }], text: "Text" })
    expect(bounds(empty, DISPLAY, measure).width).toBeCloseTo(bounds(filled, DISPLAY, measure).width, 8)
  })

  it("leaves non-text shapes render-independent", () => {
    const box = shape("rectangle", { x: 0.1, y: 0.1 }, { x: 0.4, y: 0.5 })
    expect(bounds(box, DISPLAY, measure)).toEqual(bounds(box, { width: 40, height: 80 }, measure))
  })
})

describe("moved", () => {
  it("translates every point", () => {
    const after = moved(pen([{ x: 0.2, y: 0.2 }, { x: 0.3, y: 0.3 }]), { x: 0.1, y: 0.05 })
    expect(after.points[0]?.x).toBeCloseTo(0.3, 8)
    expect(after.points[0]?.y).toBeCloseTo(0.25, 8)
    expect(after.points[1]?.x).toBeCloseTo(0.4, 8)
    expect(after.points[1]?.y).toBeCloseTo(0.35, 8)
  })

  it("stops at the edge rather than pushing points outside the image", () => {
    const after = moved(pen([{ x: 0.8, y: 0.5 }, { x: 0.9, y: 0.6 }]), { x: 0.5, y: 0 })
    // The box is 0.1 wide ending at 0.9, so it can only travel 0.1 further.
    expect(after.points[1]?.x).toBeCloseTo(1, 8)
    expect(after.points[0]?.x).toBeCloseTo(0.9, 8)
  })

  it("moves rigidly — the box keeps its size at the edge", () => {
    const before = pen([{ x: 0.8, y: 0.5 }, { x: 0.9, y: 0.6 }])
    const after = moved(before, { x: 0.5, y: 0.5 })
    expect(boundingBox(after).width).toBeCloseTo(boundingBox(before).width, 8)
    expect(boundingBox(after).height).toBeCloseTo(boundingBox(before).height, 8)
  })
})

describe("resizing", () => {
  it("moves the dragged endpoint of a two-point shape", () => {
    const after = resizing(shape("line", { x: 0.1, y: 0.1 }, { x: 0.5, y: 0.5 }), 1, { x: 0.8, y: 0.2 }, DISPLAY)
    expect(after.points).toEqual([{ x: 0.1, y: 0.1 }, { x: 0.8, y: 0.2 }])
  })

  it("clamps a dragged endpoint into the image", () => {
    const after = resizing(shape("line", { x: 0.1, y: 0.1 }, { x: 0.5, y: 0.5 }), 1, { x: 1.4, y: -0.3 }, DISPLAY)
    expect(after.points[1]).toEqual({ x: 1, y: 0 })
  })

  it("scales a freehand stroke from the opposite corner", () => {
    // Corner 0 is the top-left, so dragging it scales away from the
    // bottom-right, which must not move.
    const stroke = pen([{ x: 0.2, y: 0.2 }, { x: 0.6, y: 0.6 }])
    const after = resizing(stroke, 0, { x: 0.4, y: 0.4 }, DISPLAY)
    const box = boundingBox(after)
    expect(box.x + box.width).toBeCloseTo(0.6, 8)
    expect(box.y + box.height).toBeCloseTo(0.6, 8)
    expect(box.width).toBeCloseTo(0.2, 8)
  })

  it("scales a text annotation's font rather than its points", () => {
    const text = annotation({ tool: "text", points: [{ x: 0.1, y: 0.1 }], text: "abcd", width: 6 })
    const after = resizing(text, 0, { x: 0.3, y: 0.1 + bounds(text, DISPLAY, measure).height * 2 }, DISPLAY, measure)
    expect(after.points).toEqual(text.points)
    expect(after.width).toBeCloseTo(12, 5)
  })

  it("keeps a text size inside its limits", () => {
    const text = annotation({ tool: "text", points: [{ x: 0, y: 0 }], text: "abcd", width: 6 })
    const huge = resizing(text, 0, { x: 0.3, y: 1 }, DISPLAY, measure)
    expect(huge.width).toBeLessThanOrEqual(80)
    const tiny = resizing(text, 0, { x: 0.3, y: 0.0001 }, DISPLAY, measure)
    expect(tiny.width).toBeGreaterThanOrEqual(2)
  })

  it("ignores a handle index the shape does not have", () => {
    const line = shape("line", { x: 0.1, y: 0.1 }, { x: 0.5, y: 0.5 })
    expect(resizing(line, 7, { x: 0.9, y: 0.9 }, DISPLAY).points).toEqual(line.points)
  })

  it("maps the cursor back through the rotation before editing", () => {
    // A shape turned a half-turn: dragging its second handle to a point should
    // land that endpoint where the *un-rotated* shape would put it, or the
    // handle runs away from the cursor.
    const turned = { ...shape("line", { x: 0.2, y: 0.5 }, { x: 0.8, y: 0.5 }), rotation: Math.PI }
    const after = resizing(turned, 1, { x: 0.2, y: 0.5 }, DISPLAY)
    expect(after.points[1]?.x).toBeCloseTo(0.8, 6)
    expect(after.points[1]?.y).toBeCloseTo(0.5, 6)
  })
})

describe("rotate", () => {
  it("turns a point a quarter-turn about a centre", () => {
    const spun = rotate({ x: 10, y: 0 }, { x: 0, y: 0 }, Math.PI / 2)
    expect(spun.x).toBeCloseTo(0, 8)
    expect(spun.y).toBeCloseTo(10, 8)
  })

  it("is its own inverse at the opposite angle", () => {
    const centre = { x: 3, y: 7 }
    const there = rotate({ x: 11, y: 2 }, centre, 0.7)
    const back = rotate(there, centre, -0.7)
    expect(back.x).toBeCloseTo(11, 8)
    expect(back.y).toBeCloseTo(2, 8)
  })
})

describe("rotated", () => {
  it("points the handle at the cursor", () => {
    const box = shape("rectangle", { x: 0.4, y: 0.4 }, { x: 0.6, y: 0.6 })
    // Straight up from the centre is the handle's resting place, so a target
    // directly above should come back to no rotation.
    const up = rotated(box, { x: 0.5, y: 0.2 }, DISPLAY)
    expect(Math.abs(up.rotation)).toBeCloseTo(0, 6)
  })

  it("turns a quarter when the cursor moves to the right of the centre", () => {
    const box = shape("rectangle", { x: 0.4, y: 0.4 }, { x: 0.6, y: 0.6 })
    const right = rotated(box, { x: 0.9, y: 0.5 }, DISPLAY)
    expect(right.rotation).toBeCloseTo(Math.PI / 2, 6)
  })
})

describe("rectBetween", () => {
  it("normalises either drag direction", () => {
    const forward = rectBetween({ x: 0.2, y: 0.3 }, { x: 0.6, y: 0.8 })
    const backward = rectBetween({ x: 0.6, y: 0.8 }, { x: 0.2, y: 0.3 })
    expect(forward).toEqual(backward)
    expect(forward.x).toBeCloseTo(0.2, 8)
    expect(forward.y).toBeCloseTo(0.3, 8)
    expect(forward.width).toBeCloseTo(0.4, 8)
    expect(forward.height).toBeCloseTo(0.5, 8)
  })
})

describe("blurRegions", () => {
  it("returns only the blur-style redacts", () => {
    const blurred = { ...shape("redact", { x: 0.1, y: 0.1 }, { x: 0.4, y: 0.2 }), redactStyle: "blur" as const }
    const solid = { ...shape("redact", { x: 0.5, y: 0.5 }, { x: 0.7, y: 0.6 }), redactStyle: "solid" as const }
    const box = shape("rectangle", { x: 0, y: 0 }, { x: 1, y: 1 })
    expect(blurRegions([blurred, solid, box], null)).toHaveLength(1)
  })

  it("includes the in-progress draft, so the blur follows the drag", () => {
    const draft = { ...shape("redact", { x: 0.1, y: 0.1 }, { x: 0.4, y: 0.2 }), redactStyle: "blur" as const }
    expect(blurRegions([], draft)).toHaveLength(1)
  })

  it("skips a half-drawn region with only one point", () => {
    const half = { ...annotation({ tool: "redact", points: [{ x: 0.1, y: 0.1 }] }), redactStyle: "blur" as const }
    expect(blurRegions([half], null)).toEqual([])
  })

  it("carries each region's own strength and rotation", () => {
    const one = {
      ...shape("redact", { x: 0.1, y: 0.1 }, { x: 0.4, y: 0.2 }),
      redactStyle: "blur" as const,
      blurStrength: 0.9,
      rotation: 0.3,
    }
    expect(blurRegions([one], null)[0]).toMatchObject({ strength: 0.9, rotation: 0.3 })
  })
})
