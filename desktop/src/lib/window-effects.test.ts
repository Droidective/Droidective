import { describe, expect, it } from "vitest"

import {
  cardAlpha,
  clampedAmount,
  clampedOpacity,
  grainOpacity,
  isTranslucent,
  MAXIMUM_GRAIN_ALPHA,
  MINIMUM_OPACITY,
  percentLabel,
  withAlpha,
} from "@/lib/window-effects"

/**
 * The values are checked against ADBKit's `WindowEffectsTests` rather than
 * against this port's own behaviour: the point of the port is that the two
 * apps turn the same stored opacity into the same glass.
 */
describe("clampedOpacity", () => {
  it("pins to the slider's range", () => {
    expect(clampedOpacity(0.5)).toBe(0.5)
    expect(clampedOpacity(0)).toBe(MINIMUM_OPACITY)
    expect(clampedOpacity(-3)).toBe(MINIMUM_OPACITY)
    expect(clampedOpacity(2)).toBe(1)
  })

  /** A hand-edited or corrupt stored value must not paint an invisible window. */
  it("reads a non-number as fully opaque", () => {
    expect(clampedOpacity(Number.NaN)).toBe(1)
    expect(clampedOpacity(Number.POSITIVE_INFINITY)).toBe(1)
  })
})

describe("clampedAmount", () => {
  it("pins to 0…1 and reads a non-number as nothing", () => {
    expect(clampedAmount(0.4)).toBe(0.4)
    expect(clampedAmount(-1)).toBe(0)
    expect(clampedAmount(9)).toBe(1)
    expect(clampedAmount(Number.NaN)).toBe(0)
  })
})

describe("isTranslucent", () => {
  /**
   * The load-bearing one: at 100% the window must render exactly as it did
   * before the feature existed, or every screen changes for people who never
   * touched the slider.
   */
  it("is off at full opacity and on below it", () => {
    expect(isTranslucent(1)).toBe(false)
    expect(isTranslucent(0.999)).toBe(false)
    expect(isTranslucent(0.99)).toBe(true)
    expect(isTranslucent(MINIMUM_OPACITY)).toBe(true)
  })
})

describe("cardAlpha", () => {
  it("is opaque whenever the window is", () => {
    expect(cardAlpha(1)).toBe(1)
  })

  /**
   * A lifted surface stacks on the root wash, so it carries the contrast step
   * only. Painting it at the root's own alpha would compound to near-solid and
   * lose the glass everywhere a card sits.
   */
  it("carries the contrast step, not the root's alpha", () => {
    expect(cardAlpha(0.5)).toBeCloseTo(0.3, 5)
    expect(cardAlpha(0.9)).toBe(1)
    expect(cardAlpha(0.2)).toBeCloseTo(0.1875, 5)
  })

  it("never exceeds opaque at the floor", () => {
    expect(cardAlpha(MINIMUM_OPACITY)).toBeLessThanOrEqual(1)
  })
})

describe("grainOpacity", () => {
  /** Independent of opacity: the film is texture over solid as much as glass. */
  it("scales the slider onto the film's alpha", () => {
    expect(grainOpacity(0)).toBe(0)
    expect(grainOpacity(1)).toBe(MAXIMUM_GRAIN_ALPHA)
    expect(grainOpacity(0.5)).toBeCloseTo(MAXIMUM_GRAIN_ALPHA / 2, 5)
  })
})

describe("percentLabel", () => {
  it("rounds the way the Mac's readout does", () => {
    expect(percentLabel(1)).toBe("100%")
    expect(percentLabel(0.555)).toBe("56%")
    expect(percentLabel(0.1)).toBe("10%")
  })
})

describe("withAlpha", () => {
  it("re-expresses a hex token at an alpha", () => {
    expect(withAlpha("#1a1a1a", 0.5)).toBe("rgb(26 26 26 / 0.5)")
    expect(withAlpha("#FFFFFF", 0.25)).toBe("rgb(255 255 255 / 0.25)")
  })

  /** Opaque stays hex, so 100% is byte-for-byte the pre-feature rendering. */
  it("hands back the hex untouched at full alpha", () => {
    expect(withAlpha("#1a1a1a", 1)).toBe("#1a1a1a")
  })

  /**
   * A token that is already a function or a named colour must survive: turning
   * it into `rgb(NaN NaN NaN)` would blank the window rather than ignore the
   * setting.
   */
  it("leaves anything it cannot parse alone", () => {
    expect(withAlpha("rgb(1 2 3)", 0.5)).toBe("rgb(1 2 3)")
    expect(withAlpha("transparent", 0.5)).toBe("transparent")
    expect(withAlpha("#abc", 0.5)).toBe("#abc")
  })
})
