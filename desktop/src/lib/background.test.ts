import { describe, expect, it } from "vitest"
import {
  backgroundPalette,
  isLightHex,
  MIN_COMFORTABLE_CONTRAST,
  textContrastRatio,
  textPalette,
} from "@/lib/background"

describe("backgroundPalette", () => {
  it("reproduces the stock dark steps from the stock root", () => {
    // The whole point of deriving rather than picking: fed #1A1A1A it has to
    // land on the asset catalog's own #232323 and #333333, or a custom colour
    // would not have the hierarchy the stock one does.
    const derived = backgroundPalette("#1a1a1a")
    expect(derived?.["--color-bg-surface"]).toBe("#232323")
    expect(derived?.["--color-border-subtle"]).toBe("#333333")
  })

  it("darkens the hairline on a light background instead of lightening it", () => {
    const derived = backgroundPalette("#f5f6f7")
    expect(derived?.["--color-border-subtle"]).toBe("#e3e4e5")
    // …and brings the light theme's text with it, since the scheme follows
    // the colour rather than the Theme picker.
    expect(derived?.["--color-text-primary"]).toBe("#181a1c")
  })

  it("clamps rather than wrapping at the top of a channel", () => {
    // #FFFFFF + a lift is still white; the arithmetic must not roll over.
    expect(backgroundPalette("#ffffff")?.["--color-bg-surface"]).toBe("#ffffff")
  })

  it("answers null for something that is not a colour", () => {
    expect(backgroundPalette("nope")).toBeNull()
    expect(backgroundPalette("")).toBeNull()
  })

  it("takes the short form, as the Mac's parser does", () => {
    expect(backgroundPalette("#123")?.["--color-bg-root"]).toBe("#112233")
  })
})

describe("isLightHex", () => {
  it("splits at the Mac's 0.35 luminance threshold", () => {
    expect(isLightHex("#f7f3ec")).toBe(true)
    expect(isLightHex("#0d1b2a")).toBe(false)
    // Green is heavily weighted: a mid green reads light where a mid blue
    // does not, which is the behaviour the Rec. 709 weights give the Mac.
    expect(isLightHex("#00a000")).toBe(true)
    expect(isLightHex("#0000a0")).toBe(false)
  })
})

describe("textPalette", () => {
  it("derives the muted tone by compositing over the background", () => {
    const derived = textPalette("#ffffff", "#000000")
    // 62% white over black.
    expect(derived?.["--color-text-secondary"]).toBe("#9e9e9e")
    expect(derived?.["--color-text-primary"]).toBe("#ffffff")
  })

  it("puts tertiary a further step down, not level with secondary", () => {
    const derived = textPalette("#ffffff", "#000000")
    expect(derived?.["--color-text-tertiary"]).not.toBe(derived?.["--color-text-secondary"])
  })

  it("answers null when either colour is unusable", () => {
    expect(textPalette("nope", "#000000")).toBeNull()
    expect(textPalette("#ffffff", "nope")).toBeNull()
  })
})

describe("textContrastRatio", () => {
  it("warns about a colour close to its background and not about a legible one", () => {
    const bad = textContrastRatio("#333333", "#1a1a1a") ?? 0
    const good = textContrastRatio("#ececec", "#1a1a1a") ?? 0
    expect(bad).toBeLessThan(MIN_COMFORTABLE_CONTRAST)
    expect(good).toBeGreaterThan(MIN_COMFORTABLE_CONTRAST)
  })

  it("is symmetric — light text on dark is as legible as the reverse", () => {
    expect(textContrastRatio("#ffffff", "#000000")).toBe(
      textContrastRatio("#000000", "#ffffff"),
    )
  })
})
