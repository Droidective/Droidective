import { describe, expect, it } from "vitest"
import {
  countRows,
  matchesProperty,
  propertiesText,
  propertyGroups,
  summary,
} from "@/lib/deviceinfo"

// A slice of a real emulator dump, keys and shapes unchanged.
const properties: Record<string, string> = {
  "ro.product.model": "sdk_gphone64_arm64",
  "ro.product.manufacturer": "Google",
  "ro.product.cpu.abi": "arm64-v8a",
  "ro.build.version.release": "14",
  "ro.build.version.sdk": "34",
  "ro.build.id": "UE1A.230829.036",
  "ro.build.type": "userdebug",
  "ro.serialno": "EMULATOR34X3X11X0",
  "persist.sys.timezone": "Europe/London",
  "debug.force_rtl": "0",
  "init.svc.adbd": "running",
}

describe("summary", () => {
  it("leads with what someone actually wants to know", () => {
    expect(summary(properties).slice(0, 3)).toEqual([
      { label: "Model", value: "sdk_gphone64_arm64" },
      { label: "Manufacturer", value: "Google" },
      { label: "Android", value: "14" },
    ])
  })

  it("skips a key the device did not answer rather than showing 'unknown'", () => {
    // A phone and an emulator do not answer the same set.
    const sparse = summary({ "ro.product.model": "Pixel" })
    expect(sparse).toEqual([{ label: "Model", value: "Pixel" }])
  })

  it("skips a key answered with nothing", () => {
    expect(summary({ "ro.product.model": "" })).toEqual([])
  })
})

describe("propertyGroups", () => {
  it("groups by two dotted segments, not one", () => {
    // `ro` alone would be most of the dump in a single heap.
    const prefixes = propertyGroups(properties, "").map((group) => group.prefix)
    expect(prefixes).toContain("ro.build")
    expect(prefixes).toContain("ro.product")
    expect(prefixes).not.toContain("ro")
  })

  it("sorts the groups and the rows inside them", () => {
    const groups = propertyGroups(properties, "")
    const prefixes = groups.map((group) => group.prefix)
    expect(prefixes).toEqual(prefixes.toSorted())
    const build = groups.find((group) => group.prefix === "ro.build")
    expect(build?.rows.map((row) => row.key)).toEqual([
      "ro.build.id",
      "ro.build.type",
      "ro.build.version.release",
      "ro.build.version.sdk",
    ])
  })

  it("keeps a key with no dot in it", () => {
    const groups = propertyGroups({ bare: "yes" }, "")
    expect(groups).toEqual([{ prefix: "bare", rows: [{ key: "bare", value: "yes" }] }])
  })

  it("filters on the value as well as the key", () => {
    // Searching for what a property *says* is as common as searching its name.
    const groups = propertyGroups(properties, "Europe/London")
    expect(countRows(groups)).toBe(1)
    expect(groups[0]?.rows[0]?.key).toBe("persist.sys.timezone")
  })

  it("drops a group that has nothing left in it", () => {
    const groups = propertyGroups(properties, "timezone")
    expect(groups.map((group) => group.prefix)).toEqual(["persist.sys"])
  })

  it("returns nothing for a query that matches nothing", () => {
    expect(propertyGroups(properties, "zzzzz")).toEqual([])
    expect(countRows([])).toBe(0)
  })

  it("copes with a device that answered nothing", () => {
    expect(propertyGroups({}, "")).toEqual([])
  })
})

describe("matchesProperty", () => {
  it("is case-insensitive over both halves", () => {
    const row = { key: "ro.build.type", value: "userdebug" }
    expect(matchesProperty(row, "BUILD")).toBe(true)
    expect(matchesProperty(row, "USERDEBUG")).toBe(true)
    expect(matchesProperty(row, "   ")).toBe(true)
    expect(matchesProperty(row, "nope")).toBe(false)
  })
})

describe("propertiesText", () => {
  it("writes sorted key=value lines", () => {
    const lines = propertiesText({ b: "2", a: "1" }).split("\n")
    expect(lines).toEqual(["a=1", "b=2"])
  })

  it("is empty for nothing", () => {
    expect(propertiesText({})).toBe("")
  })
})
