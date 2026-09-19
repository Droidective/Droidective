import { describe, expect, it } from "vitest"
import { drawBlurRedactions, drawMarkup } from "@/lib/screenshot-draw"
import { annotation, type Annotation, type Size } from "@/lib/screenshot-markup"

const SIZE: Size = { width: 1000, height: 2000 }

interface Call {
  name: string
  args: unknown[]
}

/**
 * A recording stand-in for a 2-D context.
 *
 * jsdom has no canvas, and a real one would need a native dependency for one
 * module — but the canvas API *is* the boundary here, so recording the calls
 * tests the thing that matters: a highlighter has to reach it as a wider,
 * translucent stroke, and a rotation as a translate/rotate/translate around the
 * shape's own centre. A screenshot comparison would test the GPU.
 */
function recorder() {
  const calls: Call[] = []
  const state: Record<string, unknown> = {}
  const record =
    (name: string) =>
    (...args: unknown[]) => {
      calls.push({ name, args })
    }
  const ctx = {
    calls,
    state,
    save: record("save"),
    restore: record("restore"),
    beginPath: record("beginPath"),
    closePath: record("closePath"),
    moveTo: record("moveTo"),
    lineTo: record("lineTo"),
    arcTo: record("arcTo"),
    arc: record("arc"),
    ellipse: record("ellipse"),
    rect: record("rect"),
    clip: record("clip"),
    stroke: record("stroke"),
    fill: record("fill"),
    fillRect: record("fillRect"),
    strokeRect: record("strokeRect"),
    fillText: record("fillText"),
    drawImage: record("drawImage"),
    translate: record("translate"),
    rotate: record("rotate"),
    setLineDash: record("setLineDash"),
    measureText: () => ({
      width: 40,
      actualBoundingBoxAscent: 8,
      actualBoundingBoxDescent: 2,
    }),
  }
  // The style properties the code writes; recorded so a test can read them
  // back at the moment of a draw call.
  for (const key of [
    "lineCap",
    "lineJoin",
    "strokeStyle",
    "fillStyle",
    "lineWidth",
    "globalAlpha",
    "filter",
    "font",
    "textBaseline",
    "textAlign",
    "globalCompositeOperation",
  ]) {
    Object.defineProperty(ctx, key, {
      get: () => state[key],
      set: (value: unknown) => {
        state[key] = value
        calls.push({ name: `set:${key}`, args: [value] })
      },
    })
  }
  return ctx as unknown as CanvasRenderingContext2D & { calls: Call[]; state: Record<string, unknown> }
}

function names(ctx: { calls: Call[] }): string[] {
  return ctx.calls.map((call) => call.name)
}

function shape(tool: Annotation["tool"], over: Partial<Annotation> = {}): Annotation {
  return annotation({
    tool,
    points: [
      { x: 0.2, y: 0.2 },
      { x: 0.6, y: 0.5 },
    ],
    ...over,
  })
}

describe("drawMarkup", () => {
  it("strokes a pen path through each point", () => {
    const ctx = recorder()
    drawMarkup(
      ctx,
      [annotation({ tool: "pen", points: [{ x: 0, y: 0 }, { x: 0.5, y: 0.5 }, { x: 1, y: 1 }] })],
      null,
      SIZE,
    )
    expect(names(ctx).filter((n) => n === "lineTo")).toHaveLength(2)
    expect(names(ctx)).toContain("stroke")
  })

  it("draws a single tap as a dot rather than nothing", () => {
    // A click with the pen has one point; without this the tool looks broken
    // for anyone who does not drag.
    const ctx = recorder()
    drawMarkup(ctx, [annotation({ tool: "pen", points: [{ x: 0.5, y: 0.5 }] })], null, SIZE)
    expect(names(ctx)).toContain("lineTo")
    expect(names(ctx)).toContain("stroke")
  })

  it("makes a highlighter wider and translucent, as the Mac does", () => {
    const ctx = recorder()
    drawMarkup(ctx, [shape("highlighter", { width: 6 })], null, SIZE)
    // 6 per 1000px of a 1000px-wide render = 6, times the Mac's 3.5.
    expect(ctx.state["lineWidth"]).toBeCloseTo(21, 6)
    expect(ctx.state["globalAlpha"]).toBeCloseTo(0.35, 6)
  })

  it("gives an arrow a shaft and two head strokes", () => {
    const ctx = recorder()
    drawMarkup(ctx, [shape("arrow")], null, SIZE)
    // shaft: moveTo + lineTo; head: two moveTo/lineTo pairs.
    expect(names(ctx).filter((n) => n === "lineTo")).toHaveLength(3)
    expect(names(ctx).filter((n) => n === "stroke")).toHaveLength(2)
  })

  it("draws an ellipse rather than a box for the ellipse tool", () => {
    const ctx = recorder()
    drawMarkup(ctx, [shape("ellipse")], null, SIZE)
    expect(names(ctx)).toContain("ellipse")
  })

  it("fills a solid redaction at its own opacity", () => {
    const ctx = recorder()
    drawMarkup(ctx, [shape("redact", { redactStyle: "solid", fillOpacity: 0.6 })], null, SIZE)
    expect(names(ctx)).toContain("fillRect")
    expect(ctx.state["globalAlpha"]).toBeCloseTo(0.6, 6)
  })

  it("does not fill a blur redaction — that pass runs underneath", () => {
    const ctx = recorder()
    drawMarkup(ctx, [shape("redact", { redactStyle: "blur" })], null, SIZE)
    expect(names(ctx)).not.toContain("fillRect")
  })

  it("draws a label from its top-left, as the Mac anchors it", () => {
    const ctx = recorder()
    drawMarkup(ctx, [annotation({ tool: "text", points: [{ x: 0.1, y: 0.2 }], text: "hi" })], null, SIZE)
    expect(ctx.state["textBaseline"]).toBe("top")
    expect(ctx.state["textAlign"]).toBe("left")
    const call = ctx.calls.find((c) => c.name === "fillText")
    expect(call?.args).toEqual(["hi", 100, 400])
  })

  it("draws the placeholder for an empty label", () => {
    const ctx = recorder()
    drawMarkup(ctx, [annotation({ tool: "text", points: [{ x: 0, y: 0 }], text: "" })], null, SIZE)
    expect(ctx.calls.find((c) => c.name === "fillText")?.args[0]).toBe("Text")
  })

  it("turns a rotated annotation about its own centre and puts the context back", () => {
    const ctx = recorder()
    drawMarkup(ctx, [shape("rectangle", { rotation: 0.5 })], null, SIZE)
    const order = names(ctx)
    expect(order[0]).toBe("save")
    expect(order.at(-1)).toBe("restore")
    // translate → rotate → translate back, so the next annotation is unaffected.
    expect(order.slice(1, 4)).toEqual(["translate", "rotate", "translate"])
    const [to, , back] = ctx.calls.filter((c) => ["translate", "rotate"].includes(c.name))
    expect(back?.args[0]).toBeCloseTo(-(to?.args[0] as number), 6)
  })

  it("paints the draft after the committed annotations, so it is on top", () => {
    const ctx = recorder()
    drawMarkup(ctx, [shape("rectangle")], shape("ellipse"), SIZE)
    const order = names(ctx)
    expect(order.indexOf("ellipse")).toBeGreaterThan(order.indexOf("arcTo"))
  })

  it("scales the stroke with the render size", () => {
    const small = recorder()
    drawMarkup(small, [shape("line", { width: 6 })], null, { width: 500, height: 1000 })
    const large = recorder()
    drawMarkup(large, [shape("line", { width: 6 })], null, { width: 2000, height: 4000 })
    expect((large.state["lineWidth"] as number) / (small.state["lineWidth"] as number)).toBeCloseTo(4, 6)
  })
})

describe("drawBlurRedactions", () => {
  const image = {} as CanvasImageSource

  it("clips to the region and draws the whole image blurred", () => {
    const ctx = recorder()
    drawBlurRedactions(ctx, image, [shape("redact", { redactStyle: "blur" })], null, SIZE)
    const order = names(ctx)
    expect(order).toEqual([
      "save",
      "translate",
      "rotate",
      "beginPath",
      "rect",
      "clip",
      "translate",
      "set:filter",
      "drawImage",
      "restore",
    ])
    // The *whole* image, which is what clamps the edges — blurring only the
    // cropped piece fades it out and the sharp original leaks through.
    expect(ctx.calls.find((c) => c.name === "drawImage")?.args).toEqual([image, 0, 0, 1000, 2000])
  })

  it("scales the blur radius with the strength", () => {
    const weak = recorder()
    drawBlurRedactions(weak, image, [shape("redact", { redactStyle: "blur", blurStrength: 0.2 })], null, SIZE)
    const strong = recorder()
    drawBlurRedactions(strong, image, [shape("redact", { redactStyle: "blur", blurStrength: 0.8 })], null, SIZE)
    expect(weak.state["filter"]).toBe("blur(12px)")
    expect(strong.state["filter"]).toBe("blur(48px)")
  })

  it("never blurs below a floor, so a zero-strength region still hides something", () => {
    const ctx = recorder()
    drawBlurRedactions(ctx, image, [shape("redact", { redactStyle: "blur", blurStrength: 0 })], null, SIZE)
    expect(ctx.state["filter"]).toBe("blur(2px)")
  })

  it("does nothing for a solid redaction", () => {
    const ctx = recorder()
    drawBlurRedactions(ctx, image, [shape("redact", { redactStyle: "solid" })], null, SIZE)
    expect(ctx.calls).toEqual([])
  })
})
