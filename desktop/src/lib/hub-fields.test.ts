import { describe, expect, it } from "vitest"

import raw from "@/lib/__fixtures__/features.json"
import { localeOptions } from "@/lib/hub-fields"
import type { FeatureSummary } from "@/lib/wire"

// Real daemon output, captured from `POST /v1/features/list`.
const features = (raw as unknown as { features: FeatureSummary[] }).features

describe("localeOptions", () => {
  it("reads the registry's own list rather than keeping a second one", () => {
    const options = localeOptions(features)
    expect(options.length).toBeGreaterThan(3)
    // The registry's default, which the hub's picker starts on — a list that
    // did not contain it would open showing a value it could not select.
    expect(options.map((option) => option.value)).toContain("en-US")
    for (const option of options) {
      expect(option.value, "a locale with no value is unselectable").not.toBe("")
      expect(option.label, "a locale with no label is a blank menu row").not.toBe("")
    }
  })

  it("answers empty for a daemon that does not serve the feature", () => {
    // Empty rather than a built-in fallback: offering a locale this daemon has
    // never heard of would be a picker whose choices the runner rejects.
    expect(localeOptions([])).toEqual([])
  })

  it("answers empty when the feature has no locale field", () => {
    const locale = features.find((feature) => feature.id === "locale")
    expect(locale).toBeDefined()
    expect(localeOptions([{ ...(locale as FeatureSummary), fields: [] }])).toEqual([])
  })
})
