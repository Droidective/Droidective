import { describe, expect, it } from "vitest"

import type { Palette } from "@/lib/appearance"
import { glassPalette } from "@/lib/glass"

const base: Palette = {
  "--color-bg-root": "#1a1a1a",
  "--color-bg-surface": "#232323",
  "--color-bg-chrome": "#1e1e1e",
  "--color-bg-raised": "#2c2c2c",
  "--color-border-subtle": "#333333",
  "--color-text-primary": "#ececec",
}

describe("glassPalette", () => {
  /**
   * The load-bearing one: a window nobody has touched the slider on has to
   * render exactly as it did before the feature existed.
   */
  it("hands back the palette untouched at full opacity", () => {
    expect(glassPalette(base, 1)).toBe(base)
    expect(glassPalette(base, 0.999)).toBe(base)
  })

  /**
   * The root carries the window opacity; a lifted surface carries only the
   * contrast step, because it stacks on the root wash rather than replacing
   * it. At 0.5 that is `cardAlpha(0.5) === 0.3`.
   */
  it("gives the root the opacity and the lifted surfaces the step", () => {
    const glass = glassPalette(base, 0.5)
    expect(glass["--color-bg-root"]).toBe("rgb(26 26 26 / 0.5)")
    expect(glass["--color-bg-surface"]).toBe("rgb(35 35 35 / 0.3)")
    expect(glass["--color-bg-chrome"]).toBe("rgb(30 30 30 / 0.3)")
    expect(glass["--color-bg-raised"]).toBe("rgb(44 44 44 / 0.3)")
  })

  /**
   * Hairlines and text stay solid. A faded hairline is what makes a
   * translucent window read as one undifferentiated sheet.
   */
  it("leaves borders and text alone", () => {
    const glass = glassPalette(base, 0.3)
    expect(glass["--color-border-subtle"]).toBe("#333333")
    expect(glass["--color-text-primary"]).toBe("#ececec")
  })

  /** A custom background palette may not carry every token. */
  it("survives a palette missing some of the tokens", () => {
    const partial: Palette = { "--color-bg-root": "#000000" }
    expect(glassPalette(partial, 0.4)).toEqual({ "--color-bg-root": "rgb(0 0 0 / 0.4)" })
  })
})
