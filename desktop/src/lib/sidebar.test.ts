import { describe, expect, it } from "vitest"
import raw from "@/lib/__fixtures__/features.json"
import { moveBefore } from "@/lib/ordering"
import {
  CATEGORY_ORDER,
  categoryLabel,
  sidebarFeatures,
  sidebarSections,
  toggleCollapsed,
  visibleFeatures,
} from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"

// Real daemon output, captured from `POST /v1/features/list`.
const features = (raw as unknown as { features: FeatureSummary[] }).features

const plain = {
  query: "",
  sidebarOrder: [],
  categoryOrder: [],
  collapsedCategories: [],
  favorites: [],
}

describe("categories", () => {
  it("has a heading and a position for every category the daemon serves", () => {
    // The guard on the one thing held client-side that the wire does not send.
    // A category added to ADBKit lands here as a failure rather than as an
    // unlabelled group in the sidebar.
    const served = new Set(features.map((feature) => feature.category))
    for (const category of served) {
      expect(CATEGORY_ORDER).toContain(category)
    }
  })

  it("uses the Mac's headings, not the wire's case names", () => {
    expect(categoryLabel("input")).toBe("Input & Clipboard")
    expect(categoryLabel("logs")).toBe("Logs & Diagnostics")
    expect(categoryLabel("toolUX")).toBe("Tool UX")
  })

  it("makes something readable of a category it has never heard of", () => {
    expect(categoryLabel("brandNewThing")).toBe("Brand New Thing")
  })
})

describe("sidebarFeatures", () => {
  it("lists only what the engine implements", () => {
    const listed = sidebarFeatures(features)
    expect(listed.length).toBeGreaterThan(0)
    for (const feature of listed) expect(feature.implemented).toBe(true)
  })

  it("drops a feature the daemon says it cannot run", () => {
    // Asserted against a synthetic entry rather than a real id: every feature
    // the current daemon serves is implemented, so an example from the fixture
    // would be a test that passes by finding nothing. It still has to hold —
    // an older daemon, or a registry entry that lands before its runner, is
    // exactly what this filter is for.
    const unrun = { ...(features[0] as FeatureSummary), id: "not-yet", implemented: false }
    const listed = sidebarFeatures([...features, unrun]).map((feature) => feature.id)
    expect(listed).not.toContain("not-yet")
  })

  it("keeps a member of the one hub this app has not built", () => {
    // The Apps explorer's detail pane is what folds these in on the Mac, and
    // this app's `AppsPane` has no such pane — so hiding them would strand
    // them. See `lib/hubs.ts`.
    const listed = sidebarFeatures(features).map((feature) => feature.id)
    expect(listed).toContain("app-info")
  })

  it("folds away a member of a hub this app has built", () => {
    // fake-battery is reachable through the Simulate hub, which is a real pane
    // here now, so listing it as well would be the Mac's own duplication.
    const listed = sidebarFeatures(features).map((feature) => feature.id)
    expect(listed).not.toContain("fake-battery")
    expect(listed).toContain("simulate")
  })

  it("lists full-screen views alongside actions", () => {
    // The old action palette filtered these out; the sidebar is where they
    // open, so it has to offer them.
    const listed = sidebarFeatures(features).map((feature) => feature.id)
    expect(listed).toContain("logcat")
    expect(listed).toContain("file-explorer")
  })
})

describe("sidebarSections", () => {
  it("orders sections the way the Mac's sidebar does, not the way the wire arrives", () => {
    const sections = sidebarSections(features, plain).map((section) => section.category)
    // The registry serves Logs before App Management; the sidebar shows the
    // reverse, which is the whole reason the order is held client-side.
    const served = [...new Set(features.map((feature) => feature.category))]
    expect(served.indexOf("logs")).toBeLessThan(served.indexOf("appManagement"))
    expect(sections.indexOf("appManagement")).toBeLessThan(sections.indexOf("logs"))
    expect(sections[0]).toBe("input")
  })

  it("puts a feature where the user dragged it, inside its own group", () => {
    const deviceState = sidebarSections(features, plain).find(
      (section) => section.category === "deviceState",
    )
    const ids = deviceState?.features.map((feature) => feature.id) ?? []
    expect(ids.length).toBeGreaterThan(2)
    const [first, , third] = ids as [string, string, string]
    const sidebarOrder = moveBefore(third, first, features.map((feature) => feature.id))
    const moved = sidebarSections(features, { ...plain, sidebarOrder }).find(
      (section) => section.category === "deviceState",
    )
    expect(moved?.features[0]?.id).toBe(third)
  })

  it("puts a group where the user dragged it", () => {
    const categoryOrder = moveBefore("logs", "input", [...CATEGORY_ORDER])
    const sections = sidebarSections(features, { ...plain, categoryOrder })
    expect(sections[0]?.category).toBe("logs")
  })

  it("keeps a collapsed group's header but drops its rows", () => {
    const sections = sidebarSections(features, { ...plain, collapsedCategories: ["input"] })
    const input = sections.find((section) => section.category === "input")
    expect(input?.collapsed).toBe(true)
    expect(input?.features.length).toBeGreaterThan(0)
    expect(visibleFeatures(sections).map((feature) => feature.category)).not.toContain("input")
  })

  it("skips a category with nothing in it", () => {
    const onlyLogs = features.filter((feature) => feature.category === "logs")
    expect(sidebarSections(onlyLogs, plain).map((section) => section.category)).toEqual(["logs"])
  })

  it("ranks by relevance while searching, best hit first", () => {
    // The Simulate hub, not fake-battery: the hub folds in each member's
    // keywords precisely so the member's own word still lands somewhere, and
    // the member itself is no longer listed separately.
    const sections = sidebarSections(features, { ...plain, query: "battery" })
    expect(sections[0]?.features[0]?.id).toBe("simulate")
  })

  it("reveals a collapsed group's hits rather than hiding them from a search", () => {
    const sections = sidebarSections(features, {
      ...plain,
      query: "battery",
      collapsedCategories: [...CATEGORY_ORDER],
    })
    expect(visibleFeatures(sections).map((feature) => feature.id)).toContain("simulate")
  })

  it("puts a Pinned section first and lifts its members out of their groups", () => {
    const sections = sidebarSections(features, { ...plain, favorites: ["logcat", "screenshot"] })
    expect(sections[0]?.label).toBe("Pinned")
    expect(sections[0]?.features.map((feature) => feature.id)).toEqual(["logcat", "screenshot"])
    // Listed once, not in both places.
    const elsewhere = sections
      .slice(1)
      .flatMap((section) => section.features.map((feature) => feature.id))
    expect(elsewhere).not.toContain("logcat")
    expect(elsewhere).not.toContain("screenshot")
  })

  it("has no Pinned section when nothing is pinned", () => {
    expect(sidebarSections(features, plain).map((section) => section.label)).not.toContain("Pinned")
  })

  it("does not pin-order a search", () => {
    const sections = sidebarSections(features, { ...plain, query: "battery", favorites: ["logcat"] })
    expect(sections[0]?.features[0]?.id).toBe("simulate")
  })

  it("returns nothing for a query that matches nothing", () => {
    expect(sidebarSections(features, { ...plain, query: "zzzzz-no-such-thing" })).toEqual([])
  })
})

describe("toggleCollapsed", () => {
  it("adds then removes", () => {
    expect(toggleCollapsed([], "logs")).toEqual(["logs"])
    expect(toggleCollapsed(["input", "logs"], "logs")).toEqual(["input"])
  })
})
