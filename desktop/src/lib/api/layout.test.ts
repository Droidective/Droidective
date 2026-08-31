import { describe, expect, it } from "vitest"

import {
  clampedFraction,
  FRACTION_MAX,
  FRACTION_MIN,
  fractionFrom,
  leadingLength,
  MIN_PANE,
  SIDEBAR_MAX,
  SIDEBAR_MIN,
  sidebarWidth,
} from "@/lib/api/layout"

describe("sidebarWidth", () => {
  it("holds the stored width inside its own range", () => {
    expect(sidebarWidth(300, 1400)).toBe(300)
    expect(sidebarWidth(80, 1400)).toBe(SIDEBAR_MIN)
    expect(sidebarWidth(900, 1400)).toBe(SIDEBAR_MAX)
  })

  /**
   * The sidebar never takes more than a third, so the request and response
   * columns keep the room they need on a narrow window.
   */
  it("never takes more than a third of the pane", () => {
    expect(sidebarWidth(SIDEBAR_MAX, 900)).toBe(300)
  })

  /** But it also never collapses below the width its own contents need. */
  it("keeps its floor even when a third would be less", () => {
    expect(sidebarWidth(SIDEBAR_MAX, 300)).toBe(SIDEBAR_MIN)
  })

  it("survives being asked before the pane has been measured", () => {
    expect(sidebarWidth(300, 0)).toBe(300)
  })
})

describe("clampedFraction", () => {
  it("holds the split between a quarter and three quarters", () => {
    expect(clampedFraction(0.5)).toBe(0.5)
    expect(clampedFraction(0.01)).toBe(FRACTION_MIN)
    expect(clampedFraction(0.99)).toBe(FRACTION_MAX)
  })
})

describe("leadingLength", () => {
  it("splits by the fraction on a wide pane", () => {
    expect(leadingLength(1200, 0.5)).toBe(600)
    expect(leadingLength(1200, FRACTION_MIN)).toBe(300)
  })

  /**
   * The absolute floor on top of the fraction: below it the fraction alone
   * would squeeze one pane to nothing while the other kept everything.
   */
  it("applies the pane floor on both sides", () => {
    expect(leadingLength(700, FRACTION_MIN)).toBe(MIN_PANE)
    expect(leadingLength(700, FRACTION_MAX)).toBe(700 - MIN_PANE)
  })

  it("shrinks both panes evenly when there is no room for two floors", () => {
    expect(leadingLength(400, FRACTION_MIN)).toBe(200)
    expect(leadingLength(400, FRACTION_MAX)).toBe(200)
  })

  it("answers zero before the pane has been measured", () => {
    expect(leadingLength(0, 0.5)).toBe(0)
  })
})

describe("fractionFrom", () => {
  /**
   * Both halves come from the same total, so a drag cannot be converted
   * through one width and back through another — which is how a seam ends up
   * jumping when the window is resized mid-drag.
   */
  it("adds the movement as a share of the same total", () => {
    expect(fractionFrom(0.5, 120, 1200)).toBeCloseTo(0.6, 5)
    expect(fractionFrom(0.5, -120, 1200)).toBeCloseTo(0.4, 5)
  })

  it("clamps the result rather than the input", () => {
    expect(fractionFrom(0.5, 1200, 1200)).toBe(FRACTION_MAX)
    expect(fractionFrom(0.5, -1200, 1200)).toBe(FRACTION_MIN)
  })

  it("keeps the starting fraction when there is no width to move within", () => {
    expect(fractionFrom(0.5, 100, 0)).toBe(0.5)
  })
})
