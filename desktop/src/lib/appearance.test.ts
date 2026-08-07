import { describe, expect, it } from "vitest"
import {
  ACCENT_PRESETS,
  accentFor,
  DEFAULT_ACCENT,
  isLowContrast,
  normalizeHex,
  palette,
  relativeLuminance,
  resolveTheme,
  THEMES,
} from "@/lib/appearance"

describe("THEMES", () => {
  it("offers the Mac's three, in its order", () => {
    expect(THEMES.map((theme) => theme.value)).toEqual(["light", "dark", "system"])
  })
})

describe("resolveTheme", () => {
  it("follows the OS only on system", () => {
    expect(resolveTheme("system", true)).toBe("dark")
    expect(resolveTheme("system", false)).toBe("light")
    expect(resolveTheme("dark", false)).toBe("dark")
    expect(resolveTheme("light", true)).toBe("light")
  })
})

describe("palette", () => {
  it("uses the Mac's asset-catalog values, not lookalikes", () => {
    // Taken from BgRoot/TextMain .colorset — the two products are the same
    // colour rather than approximately the same colour.
    expect(palette("dark")["--color-bg-root"]).toBe("#1a1a1a")
    expect(palette("light")["--color-bg-root"]).toBe("#f5f6f7")
    expect(palette("light")["--color-text-primary"]).toBe("#181a1c")
  })

  it("defines the same token set for both themes", () => {
    // A token present in one and missing in the other would leave a stale
    // value behind when switching, which reads as a rendering bug.
    expect(Object.keys(palette("light")).toSorted()).toEqual(
      Object.keys(palette("dark")).toSorted(),
    )
  })
})

describe("accentFor", () => {
  it("darkens the default green in light mode, as BrandAccent does", () => {
    expect(accentFor(DEFAULT_ACCENT, "light")).toBe("#468a10")
    expect(accentFor(DEFAULT_ACCENT, "dark")).toBe(DEFAULT_ACCENT)
  })

  it("leaves a chosen accent exactly as chosen", () => {
    expect(accentFor("#0a84ff", "light")).toBe("#0a84ff")
  })
})

describe("normalizeHex", () => {
  it("takes the forms people actually paste", () => {
    expect(normalizeHex("#6ECC1F")).toBe("#6ecc1f")
    expect(normalizeHex("6ecc1f")).toBe("#6ecc1f")
    expect(normalizeHex("  #abc ")).toBe("#aabbcc")
  })

  it("refuses anything else rather than coercing it", () => {
    // A half-parsed colour applied silently is worse than a field that says no.
    expect(normalizeHex("")).toBeNull()
    expect(normalizeHex("#12345")).toBeNull()
    expect(normalizeHex("rebeccapurple")).toBeNull()
    expect(normalizeHex("#gggggg")).toBeNull()
  })
})

describe("relativeLuminance", () => {
  it("bounds black and white", () => {
    expect(relativeLuminance("#000000")).toBeCloseTo(0, 5)
    expect(relativeLuminance("#ffffff")).toBeCloseTo(1, 5)
  })

  it("falls back rather than throwing on nonsense", () => {
    expect(relativeLuminance("not a colour")).toBe(relativeLuminance(DEFAULT_ACCENT))
  })
})

describe("isLowContrast", () => {
  it("warns about an accent that vanishes into the background", () => {
    expect(isLowContrast("#1b1b1b", "dark")).toBe(true)
    expect(isLowContrast("#f4f5f6", "light")).toBe(true)
  })

  it("passes every preset on the theme it was chosen for", () => {
    for (const preset of ACCENT_PRESETS) {
      expect(isLowContrast(preset.value, "dark"), `${preset.label} on dark`).toBe(false)
    }
  })

  it("does not warn about the app's own default in light mode", () => {
    // The stored green really is too pale on white — which is exactly why
    // `accentFor` darkens it there. Testing the stored value would fire the
    // warning on a colour the app never paints.
    expect(isLowContrast(DEFAULT_ACCENT, "light")).toBe(true)
    expect(isLowContrast(accentFor(DEFAULT_ACCENT, "light"), "light")).toBe(false)
  })
})
