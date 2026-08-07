import { describe, expect, it } from "vitest"
import {
  canDisable,
  hiddenCount,
  isEnabled,
  isGroupEnabled,
  manageFeaturesLabel,
  withEnabled,
  withGroupEnabled,
} from "@/lib/catalog"
import type { FeatureSummary } from "@/lib/wire"

const feature = (id: string, kind = "view"): FeatureSummary =>
  ({ id, kind }) as unknown as FeatureSummary

describe("the default", () => {
  it("has everything on before anything is turned off", () => {
    // The persisted set is what is *disabled*, so a feature shipped after this
    // layout was written is on without a migration having to notice it.
    expect(isEnabled("brand-new-feature", [])).toBe(true)
  })
})

describe("canDisable", () => {
  it("refuses the app's own chrome", () => {
    // Home, the catalog and About have nothing to declutter, and no way back
    // if one vanished.
    expect(canDisable(feature("catalog", "system"))).toBe(false)
    expect(canDisable(feature("logcat"))).toBe(true)
  })
})

describe("withEnabled", () => {
  it("turns one off and back on", () => {
    const off = withEnabled([], "logcat", false)
    expect(isEnabled("logcat", off)).toBe(false)
    expect(isEnabled("logcat", withEnabled(off, "logcat", true))).toBe(true)
  })

  it("does not list the same feature twice", () => {
    const once = withEnabled([], "logcat", false)
    expect(withEnabled(once, "logcat", false)).toEqual(["logcat"])
  })

  it("leaves the input alone", () => {
    const original = ["logcat"]
    withEnabled(original, "apps", false)
    expect(original).toEqual(["logcat"])
  })
})

describe("withGroupEnabled", () => {
  const members = [feature("logcat"), feature("apps"), feature("catalog", "system")]

  it("turns every disableable member off", () => {
    const off = withGroupEnabled([], members, false)
    expect(isEnabled("logcat", off)).toBe(false)
    expect(isEnabled("apps", off)).toBe(false)
  })

  it("never turns off a system feature, even in a group", () => {
    expect(withGroupEnabled([], members, false)).not.toContain("catalog")
  })

  it("turns a whole group back on", () => {
    const off = withGroupEnabled([], members, false)
    expect(withGroupEnabled(off, members, true)).toEqual([])
  })
})

describe("isGroupEnabled", () => {
  const members = [feature("logcat"), feature("apps")]

  it("is on while anything in it is showing", () => {
    // So a partly-hidden group still offers "Disable all", which is what
    // someone means by it.
    expect(isGroupEnabled(members, ["logcat"])).toBe(true)
  })

  it("is off only once everything is hidden", () => {
    expect(isGroupEnabled(members, ["logcat", "apps"])).toBe(false)
  })

  it("ignores a system member, which can never be off", () => {
    expect(isGroupEnabled([feature("catalog", "system")], [])).toBe(false)
  })
})

describe("hiddenCount and its label", () => {
  const features = [feature("logcat"), feature("apps"), feature("catalog", "system")]

  it("counts only what someone actually turned off", () => {
    expect(hiddenCount(features, [])).toBe(0)
    expect(hiddenCount(features, ["logcat"])).toBe(1)
  })

  it("does not count a system feature that happens to be listed", () => {
    expect(hiddenCount(features, ["catalog"])).toBe(0)
  })

  it("reminds you something is hidden, and says how much", () => {
    // Without this the footer is the only trace of a feature hidden months ago.
    expect(manageFeaturesLabel(0)).toBe("Manage features")
    expect(manageFeaturesLabel(1)).toBe("+ 1 more feature")
    expect(manageFeaturesLabel(4)).toBe("+ 4 more features")
  })
})
