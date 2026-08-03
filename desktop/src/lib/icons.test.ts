import { describe, expect, it } from "vitest"
import raw from "@/lib/__fixtures__/features.json"
import { featuresWithIcons, iconForFeature } from "@/lib/icons"
import type { FeatureSummary } from "@/lib/wire"

// Real daemon output, captured from `POST /v1/features/list`.
const features = (raw as unknown as { features: FeatureSummary[] }).features

describe("iconForFeature", () => {
  it("has a glyph for every feature the daemon serves", () => {
    // The guard on a table the wire cannot supply: a feature added to the
    // registry lands here as a failure rather than as a row quietly wearing
    // its category's icon.
    const missing = features
      .filter((feature) => !featuresWithIcons().includes(feature.id))
      .map((feature) => feature.id)
    expect(missing).toEqual([])
  })

  it("has no entry for a feature that no longer exists", () => {
    const served = new Set(features.map((feature) => feature.id))
    expect(featuresWithIcons().filter((id) => !served.has(id))).toEqual([])
  })

  it("gives neighbours in a category different glyphs", () => {
    // The whole point: before this, every Connection feature was one Wi-Fi
    // symbol repeated eight times.
    const connection = features.filter((feature) => feature.category === "connection")
    const glyphs = new Set(connection.map((feature) => iconForFeature(feature.id, feature.category)))
    expect(connection.length).toBeGreaterThan(4)
    expect(glyphs.size).toBe(connection.length)
  })

  it("falls back to the category for an id it has never seen", () => {
    // Two unknown ids in a category agree with each other and differ from
    // another category's — which is what "fell back to the category" means.
    expect(iconForFeature("brand-new-a", "logs")).toBe(iconForFeature("brand-new-b", "logs"))
    expect(iconForFeature("brand-new-a", "logs")).not.toBe(iconForFeature("brand-new-a", "input"))
  })

  it("falls back again for a category it has never seen", () => {
    expect(iconForFeature("brand-new-feature", "brandNewCategory")).toBeTypeOf("object")
  })
})
