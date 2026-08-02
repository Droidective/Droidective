import { describe, expect, it } from "vitest"
import raw from "@/lib/__fixtures__/features.json"
import { moveHighlight, paletteResults, rankFeatures, relevance, togglePinned } from "@/lib/palette"
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

describe("rankFeatures", () => {
  it("puts the best match first", () => {
    expect(rankFeatures(features, "battery")[0]?.id).toBe("fake-battery")
  })

  it("preserves the incoming order for equal scores", () => {
    // Callers hand this the registry order, and a stable list is what keeps
    // rows from reshuffling under the cursor as someone types.
    const all = rankFeatures(features, "")
    expect(all.map((feature) => feature.id)).toEqual(features.map((feature) => feature.id))
  })

  it("drops what scores nothing", () => {
    expect(rankFeatures(features, "zzzzz-no-such-thing")).toEqual([])
  })

  it("leaves the choice of what to offer to its caller", () => {
    // Deliberately not filtered here: the sidebar wants views as well as
    // actions, and a palette over commands would choose differently again.
    expect(rankFeatures(features, "").map((feature) => feature.id)).toContain("logcat")
  })
})

describe("paletteResults", () => {
  it("opens on what you pinned, in the order you pinned it", () => {
    const results = paletteResults(features, "", ["logcat", "screenshot"])
    expect(results.slice(0, 2).map((feature) => feature.id)).toEqual(["logcat", "screenshot"])
  })

  it("lists a pinned feature once, not twice", () => {
    const ids = paletteResults(features, "", ["logcat"]).map((feature) => feature.id)
    expect(ids.filter((id) => id === "logcat")).toHaveLength(1)
    expect(ids).toHaveLength(features.length)
  })

  it("lets relevance decide once there is a query", () => {
    // A weakly-matching pin sitting above an exact match would make the
    // ranking a lie, so pins are not promoted here.
    const results = paletteResults(features, "battery", ["logcat"])
    expect(results[0]?.id).toBe("fake-battery")
    expect(results.map((feature) => feature.id)).not.toContain("logcat")
  })

  it("ignores a pinned id that is no longer served", () => {
    const ids = paletteResults(features, "", ["gone-feature"]).map((feature) => feature.id)
    expect(ids).toHaveLength(features.length)
  })
})

describe("moveHighlight", () => {
  it("wraps at both ends", () => {
    expect(moveHighlight(3, 2, 1)).toBe(0)
    expect(moveHighlight(3, 0, -1)).toBe(2)
    expect(moveHighlight(3, 0, 1)).toBe(1)
  })

  it("stays put with nothing to highlight", () => {
    expect(moveHighlight(0, 0, 1)).toBe(0)
  })
})

describe("togglePinned", () => {
  it("appends then removes, keeping the pinning order", () => {
    expect(togglePinned([], "logcat")).toEqual(["logcat"])
    expect(togglePinned(["apps"], "logcat")).toEqual(["apps", "logcat"])
    expect(togglePinned(["apps", "logcat"], "apps")).toEqual(["logcat"])
  })
})
