import { describe, expect, it } from "vitest"
import {
  moveInGrid,
  openableScreens,
  panelEligibleActions,
  quickActions,
  quickCommands,
} from "@/lib/quick-actions"
import type { CustomCommand, FeatureSummary } from "@/lib/wire"

const feature = (
  id: string,
  kind: string,
  extra: Partial<FeatureSummary> = {},
): FeatureSummary =>
  ({
    id,
    title: id,
    subtitle: null,
    keywords: [],
    category: "Device",
    kind,
    implemented: true,
    ...extra,
  }) as FeatureSummary

const catalog = [
  feature("screenshot", "instantAction"),
  feature("dark-mode", "toggleAction", { absorbedBy: "simulate" }),
  feature("deep-link", "formAction"),
  feature("logcat", "view"),
  feature("frida-console", "view", { implemented: false }),
  feature("simulate", "view"),
]

const none = { query: "", disabled: [], favorites: [], hidden: [] }

describe("quickActions", () => {
  it("offers the three runnable kinds and no screens", () => {
    expect(quickActions(catalog, none).map((entry) => entry.id)).toEqual([
      "screenshot",
      "dark-mode",
      "deep-link",
    ])
  })

  it("keeps a hub member — the members are what the panel is for", () => {
    // The Mac's rule, and the one easy to get backwards: hiding hub members
    // here would empty the panel of most of what it offers.
    expect(quickActions(catalog, none).some((entry) => entry.id === "dark-mode")).toBe(true)
  })

  it("drops a hub member when its hub is turned off, not when it is", () => {
    // The catalog only lets a member be turned off through its hub, so the
    // hub is where its enabledness is read from.
    expect(
      quickActions(catalog, { ...none, disabled: ["simulate"] }).map((entry) => entry.id),
    ).toEqual(["screenshot", "deep-link"])
    expect(
      quickActions(catalog, { ...none, disabled: ["dark-mode"] }).map((entry) => entry.id),
    ).toEqual(["screenshot", "dark-mode", "deep-link"])
  })

  it("leaves out an action hidden from the panel", () => {
    expect(
      quickActions(catalog, { ...none, hidden: ["screenshot"] }).map((entry) => entry.id),
    ).toEqual(["dark-mode", "deep-link"])
  })

  it("leads with the pinned actions when nothing is typed", () => {
    expect(
      quickActions(catalog, { ...none, favorites: ["deep-link"] }).map((entry) => entry.id),
    ).toEqual(["deep-link", "screenshot", "dark-mode"])
  })

  it("does not promote a pin once there is a query", () => {
    // A weakly-matching pin above an exact match would make the ranking a lie.
    expect(
      quickActions(catalog, { ...none, query: "dark", favorites: ["deep-link"] }).map(
        (entry) => entry.id,
      ),
    ).toEqual(["dark-mode"])
  })

  it("never offers something the engine does not implement", () => {
    expect(panelEligibleActions(catalog, []).some((entry) => entry.id === "frida-console")).toBe(
      false,
    )
  })
})

describe("openableScreens", () => {
  it("lists the screens and not the actions", () => {
    expect(openableScreens(catalog, { query: "", disabled: [] }).map((entry) => entry.id)).toEqual([
      "logcat",
      "simulate",
    ])
  })

  it("leaves out a screen turned off in the catalog", () => {
    expect(
      openableScreens(catalog, { query: "", disabled: ["logcat"] }).map((entry) => entry.id),
    ).toEqual(["simulate"])
  })
})

describe("quickCommands", () => {
  const commands = [
    { id: "1", name: "Clear Metro", command: "adb shell am force-stop x" },
    { id: "2", name: "Tail", command: "adb logcat" },
  ] as CustomCommand[]

  it("keeps the saved order with no query", () => {
    expect(quickCommands(commands, "").map((entry) => entry.id)).toEqual(["1", "2"])
  })

  it("matches the command text as well as the name", () => {
    expect(quickCommands(commands, "force-stop").map((entry) => entry.id)).toEqual(["1"])
  })
})

describe("moveInGrid", () => {
  it("steps left and right across rows rather than stopping at a column edge", () => {
    expect(moveInGrid(10, 5, "left", 5)).toBe(4)
    expect(moveInGrid(10, 4, "right", 5)).toBe(5)
  })

  it("stops at both ends instead of wrapping around the whole grid", () => {
    expect(moveInGrid(10, 0, "left", 5)).toBe(0)
    expect(moveInGrid(10, 9, "right", 5)).toBe(9)
  })

  it("moves a row at a time", () => {
    expect(moveInGrid(12, 1, "down", 5)).toBe(6)
    expect(moveInGrid(12, 6, "up", 5)).toBe(1)
  })

  it("lands on the last cell when the row below is short", () => {
    // 12 items, 5 across: the last row holds two. Down from index 8 must go
    // somewhere rather than off the end.
    expect(moveInGrid(12, 8, "down", 5)).toBe(11)
  })

  it("stays in the first row when there is nothing above", () => {
    expect(moveInGrid(12, 2, "up", 5)).toBe(2)
  })

  it("answers zero for an empty list", () => {
    expect(moveInGrid(0, 0, "down", 5)).toBe(0)
  })
})
