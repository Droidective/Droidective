import { describe, expect, it } from "vitest"
import { featureOfTrayCommand, trayFeatures, trayMenu } from "@/lib/tray"
import type { FeatureSummary } from "@/lib/wire"

const feature = (id: string, kind: string, title = id): FeatureSummary =>
  ({ id, title, kind, category: "Device", implemented: true }) as FeatureSummary

const catalog = [
  feature("screenshot", "instantAction", "Screenshot"),
  feature("scrcpy", "view", "Mirror Screen"),
  feature("dark-mode", "toggleAction", "Dark Mode"),
  feature("clear-data", "instantAction", "Clear App Data"),
  feature("logcat", "view", "Logcat"),
]

const none = { chosen: [], favorites: [], disabled: [] }

describe("trayFeatures", () => {
  it("shows what the user chose, in the order they chose it", () => {
    const listed = trayFeatures(catalog, { ...none, chosen: ["logcat", "dark-mode"] })
    expect(listed.map((entry) => entry.id)).toEqual(["logcat", "dark-mode"])
  })

  it("drops a chosen id that is no longer a feature", () => {
    // A registry can lose an id between releases; the saved list cannot.
    const listed = trayFeatures(catalog, { ...none, chosen: ["logcat", "gone"] })
    expect(listed.map((entry) => entry.id)).toEqual(["logcat"])
  })

  it("falls back to the pinned features when nothing was chosen", () => {
    const listed = trayFeatures(catalog, { ...none, favorites: ["logcat"] })
    expect(listed.map((entry) => entry.id)).toEqual(["logcat"])
  })

  it("falls back again to the enabled instant actions, less the two with rows of their own", () => {
    expect(trayFeatures(catalog, none).map((entry) => entry.id)).toEqual(["clear-data"])
  })

  it("leaves out an instant action turned off in the catalog", () => {
    expect(trayFeatures(catalog, { ...none, disabled: ["clear-data"] })).toEqual([])
  })

  it("keeps a chosen feature that is turned off — choosing it is the stronger signal", () => {
    const listed = trayFeatures(catalog, { ...none, chosen: ["logcat"], disabled: ["logcat"] })
    expect(listed.map((entry) => entry.id)).toEqual(["logcat"])
  })
})

describe("trayMenu", () => {
  it("names the device at the top, as a label rather than a command", () => {
    const [first] = trayMenu({ deviceLabel: "Pixel 8", features: [] })
    expect(first).toEqual({ id: "tray.device", label: "Pixel 8", enabled: false })
  })

  it("says No device when there is none, as the Mac does", () => {
    const [first] = trayMenu({ deviceLabel: null, features: [] })
    expect(first?.label).toBe("No device")
  })

  it("always offers Screenshot, Mirror Screen, Open and Quit", () => {
    const ids = trayMenu({ deviceLabel: null, features: [] }).map((entry) => entry.id)
    expect(ids).toContain("tray.screenshot")
    expect(ids).toContain("tray.mirror")
    expect(ids).toContain("tray.open")
    expect(ids).toContain("tray.quit")
  })

  it("does not leave a separator with nothing under it", () => {
    // Two separators in a row, or one at the end, is what an empty feature
    // list produces if the section is written unconditionally.
    const entries = trayMenu({ deviceLabel: null, features: [] })
    const ids = entries.map((entry) => entry.id)
    expect(ids.at(-1)).toBe("tray.quit")
    for (const [index, entry] of entries.entries()) {
      if (entry.id !== "") continue
      expect(entries[index + 1]?.id, "a separator with nothing after it").not.toBe("")
    }
  })

  it("prefixes a feature row so a click can be told from the fixed rows", () => {
    const entries = trayMenu({ deviceLabel: null, features: [feature("logcat", "view", "Logcat")] })
    const row = entries.find((entry) => entry.label === "Logcat")
    expect(row?.id).toBe("feature.logcat")
    expect(featureOfTrayCommand("feature.logcat")).toBe("logcat")
    expect(featureOfTrayCommand("tray.quit")).toBeNull()
  })
})
