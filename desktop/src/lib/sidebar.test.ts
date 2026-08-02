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
    // Registry entries with no runner on the Mac either.
    expect(listed.map((feature) => feature.id)).not.toContain("simulate")
  })

  it("keeps hub members, which this app has no hub to reach them through", () => {
    const listed = sidebarFeatures(features).map((feature) => feature.id)
    expect(listed).toContain("fake-battery")
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
    const sections = sidebarSections(features, { ...plain, query: "battery" })
    expect(sections[0]?.features[0]?.id).toBe("fake-battery")
  })

  it("reveals a collapsed group's hits rather than hiding them from a search", () => {
    const sections = sidebarSections(features, {
      ...plain,
      query: "battery",
      collapsedCategories: [...CATEGORY_ORDER],
    })
    expect(visibleFeatures(sections).map((feature) => feature.id)).toContain("fake-battery")
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
