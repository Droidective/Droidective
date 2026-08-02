import { describe, expect, it } from "vitest"
import {
  clampedFraction,
  DIVIDER_WIDTH,
  fractionForDrag,
  MAX_FRACTION,
  MIN_FRACTION,
  leftWidth,
} from "@/lib/panes"

describe("clampedFraction", () => {
  it("holds the split between 30 and 70 per cent", () => {
    expect(clampedFraction(0.5)).toBe(0.5)
    expect(clampedFraction(0.05)).toBe(MIN_FRACTION)
    expect(clampedFraction(0.95)).toBe(MAX_FRACTION)
  })
})

describe("leftWidth", () => {
  const total = 1200

  it("splits the available width by the fraction", () => {
    expect(leftWidth(total, 0.5)).toBe((total - DIVIDER_WIDTH) / 2)
  })

  it("keeps both panes above the absolute floor on a wide window", () => {
    // 30% of 1192 is 357, comfortably past the 320px floor.
    expect(leftWidth(total, MIN_FRACTION)).toBeCloseTo((total - DIVIDER_WIDTH) * MIN_FRACTION, 5)
  })

  it("shrinks both panes evenly rather than pushing one off-screen", () => {
    // On a window too tight for two 320px panes, the floor becomes half —
    // which is the case that used to push the right pane off the edge.
    const tight = 500
    const available = tight - DIVIDER_WIDTH
    expect(leftWidth(tight, 0.3)).toBe(available / 2)
    expect(leftWidth(tight, 0.7)).toBe(available / 2)
  })

  it("survives a window with no room at all", () => {
    expect(leftWidth(0, 0.5)).toBe(0)
    expect(leftWidth(DIVIDER_WIDTH, 0.5)).toBe(0)
  })
})

describe("fractionForDrag", () => {
  it("turns a divider position into a clamped fraction", () => {
    const total = 1000
    const available = total - DIVIDER_WIDTH
    expect(fractionForDrag(available / 2, total)).toBeCloseTo(0.5, 5)
    // The drag and the layout agree on the bounds — they did not always.
    expect(fractionForDrag(10, total)).toBe(MIN_FRACTION)
    expect(fractionForDrag(available, total)).toBe(MAX_FRACTION)
  })

  it("does not divide by a window with no width", () => {
    expect(fractionForDrag(100, 0)).toBe(MIN_FRACTION)
  })
})
