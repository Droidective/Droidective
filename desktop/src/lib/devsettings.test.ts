import { describe, expect, it } from "vitest"
import {
  DEV_SECTIONS,
  nearestChoice,
  placedToggleIDs,
  scaleLabel,
  scaleSelection,
  togglesFor,
} from "@/lib/devsettings"
import raw from "@/lib/__fixtures__/devsettings.json"
import type { DevSettingsResponse, DevToggle } from "@/lib/wire"

// Real daemon output, captured from `POST /v1/devsettings/read`.
const served = raw as unknown as DevSettingsResponse

describe("the section table", () => {
  it("places every toggle the daemon serves", () => {
    // The guard on the one thing held client-side. A toggle added to
    // `DeveloperSettingsService` lands here as a failure rather than as a row
    // that silently never appears on Windows and Linux.
    const placed = new Set(placedToggleIDs())
    for (const toggle of served.toggles) {
      expect(placed, `${toggle.id} is served but no section lists it`).toContain(toggle.id)
    }
  })

  it("names no toggle the daemon does not serve", () => {
    // The other direction: a toggle removed from ADBKit leaves a dead id here,
    // and a dead id is a section that renders one row short for no reason.
    const servedIDs = new Set(served.toggles.map((toggle) => toggle.id))
    for (const id of placedToggleIDs()) {
      expect(servedIDs, `${id} is listed but the daemon does not serve it`).toContain(id)
    }
  })

  it("keeps the Mac's section order, with Animations third", () => {
    // Not alphabetical and not "switches then pickers": this is the order
    // `DeveloperSettingsView.form` lists them in, and the whole point of the
    // port is that the two screens read the same top to bottom.
    expect(DEV_SECTIONS.map((section) => section.title)).toEqual([
      "Input",
      "Drawing",
      "Animations",
      "Apps",
    ])
  })

  it("places no toggle in two sections", () => {
    const placed = placedToggleIDs()
    expect(new Set(placed).size).toBe(placed.length)
  })
})

describe("togglesFor", () => {
  const first = DEV_SECTIONS[0]

  it("returns the section's rows in the section's order, not the wire's", () => {
    if (first === undefined || first.kind !== "toggles") throw new Error("no toggle section")
    const reversed = served.toggles.toReversed()
    expect(togglesFor(first, reversed).map((toggle) => toggle.id)).toEqual(first.toggles)
  })

  it("drops an id the daemon did not serve rather than rendering a blank row", () => {
    if (first === undefined || first.kind !== "toggles") throw new Error("no toggle section")
    expect(togglesFor(first, [])).toEqual([])
  })

  it("has nothing to return for the scales section", () => {
    const scales = DEV_SECTIONS.find((section) => section.kind === "scales")
    if (scales === undefined) throw new Error("no scales section")
    expect(togglesFor(scales, served.toggles)).toEqual([])
  })

  it("carries the daemon's title and detail through untouched", () => {
    if (first === undefined || first.kind !== "toggles") throw new Error("no toggle section")
    const [row] = togglesFor(first, served.toggles)
    const source = served.toggles.find((toggle) => toggle.id === row?.id)
    expect(row).toEqual(source)
  })
})

describe("scaleLabel", () => {
  it("calls zero Off, as Developer Options does", () => {
    // "0×" would read as a multiplier; the platform means "no animations".
    expect(scaleLabel(0)).toBe("Off")
  })

  it("prints a whole number bare", () => {
    expect(scaleLabel(1)).toBe("1×")
    expect(scaleLabel(2)).toBe("2×")
  })

  it("keeps a fractional step's fraction", () => {
    expect(scaleLabel(0.5)).toBe("0.5×")
    expect(scaleLabel(1.5)).toBe("1.5×")
  })
})

describe("nearestChoice", () => {
  const choices = served.scaleChoices

  it("returns an offered step unchanged", () => {
    for (const choice of choices) expect(nearestChoice(choice, choices)).toBe(choice)
  })

  it("snaps a value nothing offers to the closest step", () => {
    // Anything on the device can write that key, so the picker has to show
    // something true rather than nothing at all.
    expect(nearestChoice(0.75, choices)).toBe(0.5)
    expect(nearestChoice(3, choices)).toBe(2)
    expect(nearestChoice(99, choices)).toBe(10)
  })

  it("does not snap away from zero for a small value", () => {
    expect(nearestChoice(0.1, choices)).toBe(0)
  })

  it("leaves the value alone when nothing is on offer", () => {
    expect(nearestChoice(1.25, [])).toBe(1.25)
  })
})

describe("scaleSelection", () => {
  it("resolves a device's reading against the offered steps", () => {
    const scale = { id: "window-scale", title: "Window animation scale", value: 0.9 }
    expect(scaleSelection(scale, served.scaleChoices)).toBe(1)
  })
})

describe("the captured fixture", () => {
  it("carries the definitions, not just the values", () => {
    // If this ever fails, the daemon stopped sending the service's table and
    // every title on this screen would have to be re-typed client-side.
    const withText = served.toggles.filter(
      (toggle: DevToggle) => toggle.title !== "" && toggle.detail !== "",
    )
    expect(withText.length).toBe(served.toggles.length)
  })

  it("carries the scale steps the service offers", () => {
    expect(served.scaleChoices).toEqual([0, 0.5, 1, 1.5, 2, 5, 10])
  })
})
