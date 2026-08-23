import { describe, expect, it } from "vitest"
import {
  clampZoomStep,
  DEFAULT_ZOOM_STEP,
  ZOOM_STEPS,
  zoomLabel,
  zoomScale,
} from "@/lib/zoom"

describe("zoom steps", () => {
  it("has the Mac's steps, with the default at exactly 1", () => {
    // The same number of presses has to land on the same size in both apps.
    expect([...ZOOM_STEPS]).toEqual([0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0])
    expect(ZOOM_STEPS[DEFAULT_ZOOM_STEP]).toBe(1)
  })
})

describe("clampZoomStep", () => {
  it("keeps a step inside the range", () => {
    expect(clampZoomStep(0)).toBe(0)
    expect(clampZoomStep(-3)).toBe(0)
    expect(clampZoomStep(99)).toBe(ZOOM_STEPS.length - 1)
  })

  it("falls back to the default for a value that is not a step", () => {
    // Persisted JSON a previous version wrote, or NaN out of a parse.
    expect(clampZoomStep(Number.NaN)).toBe(DEFAULT_ZOOM_STEP)
    expect(clampZoomStep(Number.POSITIVE_INFINITY)).toBe(DEFAULT_ZOOM_STEP)
  })

  it("rounds a fractional step rather than indexing between two", () => {
    expect(clampZoomStep(2.4)).toBe(2)
    expect(clampZoomStep(2.6)).toBe(3)
  })
})

describe("zoomScale", () => {
  it("is 1 at the default and never undefined out of range", () => {
    expect(zoomScale(DEFAULT_ZOOM_STEP)).toBe(1)
    expect(zoomScale(-5)).toBe(0.8)
    expect(zoomScale(500)).toBe(2)
  })
})

describe("zoomLabel", () => {
  it("reads as a whole percentage", () => {
    // 1.15 is 114.99999999999999% in binary floating point.
    expect(zoomLabel(3)).toBe("115%")
    expect(zoomLabel(DEFAULT_ZOOM_STEP)).toBe("100%")
    expect(zoomLabel(0)).toBe("80%")
  })
})
