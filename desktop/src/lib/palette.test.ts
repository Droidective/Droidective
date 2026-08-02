import { describe, expect, it } from "vitest"
import raw from "@/lib/__fixtures__/features.json"
import { categoryLabel, groupByCategory, relevance, searchActions } from "@/lib/palette"
import type { FeatureSummary } from "@/lib/wire"

// Real daemon output, captured from `POST /v1/features/list` rather than
// hand-written — the same reason ADBKit replays recorded adb output. A
// hand-made fixture would agree with whatever this file assumed.
const features = (raw as unknown as { features: FeatureSummary[] }).features

function byID(id: string): FeatureSummary {
  const feature = features.find((candidate) => candidate.id === id)
  if (!feature) throw new Error(`the fixture has no feature ${id}`)
  return feature
}

describe("relevance", () => {
  it("ranks an exact title above a prefix, a prefix above a substring", () => {
    const screenshot = byID("screenshot")
    expect(relevance(screenshot, "Screenshot")).toBe(100)
    expect(relevance(screenshot, "screen")).toBe(80)
    expect(relevance(screenshot, "eensh")).toBe(60)
  })

  it("falls back to keywords, then the subtitle", () => {
    const battery = byID("fake-battery")
    // "Fake Battery" — the title has no "unplug", so this can only be a
    // keyword hit.
    expect(relevance(battery, "unplug")).toBe(40)
    expect(relevance(battery, "nplugged")).toBe(30)
  })

  it("scores nothing for a query that matches nowhere", () => {
    expect(relevance(byID("screenshot"), "kubernetes")).toBe(0)
  })

  it("treats an empty query as a match for everything", () => {
    expect(relevance(byID("screenshot"), "")).toBe(1)
    expect(relevance(byID("screenshot"), "   ")).toBe(1)
  })

  it("matches every word of a multi-word query, contiguous or not", () => {
    // "Copy Device IP" — neither "copy ip" nor "ip copy" is a substring.
    const ip = byID("get-ip")
    expect(relevance(ip, "copy ip")).toBe(50)
    expect(relevance(ip, "ip copy")).toBe(50)
    expect(relevance(ip, "copy kubernetes")).toBe(0)
  })

  it("keeps the registry's keyword vocabulary across the wire", () => {
    // The reason `keywords` had to be added to the daemon's summary: without
    // it this is 0 and the hub stops being findable by what it contains.
    expect(relevance(byID("simulate"), "battery")).toBeGreaterThan(0)
  })
})

describe("searchActions", () => {
  it("lists only implemented action features", () => {
    const results = searchActions(features, "")
    expect(results.length).toBeGreaterThan(0)
    for (const feature of results) {
      expect(feature.implemented).toBe(true)
      expect(["instantAction", "formAction", "toggleAction"]).toContain(feature.kind)
    }
    // Hubs and full-screen views are not runnable from this app yet.
    expect(results.map((feature) => feature.id)).not.toContain("simulate")
    expect(results.map((feature) => feature.id)).not.toContain("logcat")
  })

  it("keeps hub members reachable", () => {
    // They are most of the runnable surface: hiding them the way the Mac's
    // catalog does would leave this app with almost nothing to run, because
    // it has no hub screens to reach them through.
    const results = searchActions(features, "")
    const absorbed = results.filter((feature) => feature.isAbsorbedByHub)
    expect(absorbed.length).toBeGreaterThan(results.length / 2)
    expect(results.map((feature) => feature.id)).toContain("fake-battery")
  })

  it("puts the best match first", () => {
    const results = searchActions(features, "battery")
    expect(results[0]?.id).toBe("fake-battery")
  })

  it("preserves registry order for equal scores", () => {
    const all = searchActions(features, "")
    const registryOrder = features
      .filter((feature) => all.some((match) => match.id === feature.id))
      .map((feature) => feature.id)
    expect(all.map((feature) => feature.id)).toEqual(registryOrder)
  })

  it("returns nothing for a query that matches nothing", () => {
    expect(searchActions(features, "zzzzz-no-such-thing")).toEqual([])
  })
})

describe("groupByCategory", () => {
  it("groups without reordering within a group", () => {
    const groups = groupByCategory(searchActions(features, ""))
    expect(groups.length).toBeGreaterThan(1)
    const flattened = groups.flatMap((group) => group.features.map((feature) => feature.id))
    expect(new Set(flattened).size).toBe(flattened.length)
  })

  it("turns a wire case name into something readable", () => {
    expect(categoryLabel("deviceState")).toBe("Device State")
    expect(categoryLabel("input")).toBe("Input")
    expect(categoryLabel("reactNative")).toBe("React Native")
  })
})
