import { describe, expect, it } from "vitest"

import {
  claimantOf,
  EXCLUSIVE_FEATURE_IDS,
  hasOtherWindows,
  isExclusive,
  selfClaim,
  windowHolding,
  windowTint,
  windowTitle,
  type WindowClaim,
} from "@/lib/workspaces"

function claim(over: Partial<WindowClaim> & { label: string }): WindowClaim {
  return { ordinal: 1, serial: null, features: [], ...over }
}

describe("isExclusive", () => {
  it("names the four that cannot run twice on one device", () => {
    expect(isExclusive("scrcpy")).toBe(true)
    expect(isExclusive("screen-record")).toBe(true)
    expect(isExclusive("js-console")).toBe(true)
    expect(isExclusive("frida-console")).toBe(true)
  })

  /**
   * The Mac keeps `mirror-wall` out deliberately: a whole-pane banner over the
   * window's selected device would block five working tiles because of the
   * sixth, so the wall contends per tile instead.
   */
  it("leaves the mirror wall out", () => {
    expect(isExclusive("mirror-wall")).toBe(false)
  })

  it("says nothing about the features that duplicate fine", () => {
    for (const id of ["logcat", "apps", "file-explorer", "performance", "api-client"]) {
      expect(isExclusive(id), `${id} should be duplicable`).toBe(false)
    }
  })
})

describe("claimantOf", () => {
  const claims = [
    claim({ label: "main", ordinal: 1, serial: "A", features: ["scrcpy", "logcat"] }),
    claim({ label: "w1", ordinal: 2, serial: "B", features: ["js-console"] }),
  ]

  it("finds the other window running the feature on that device", () => {
    expect(claimantOf("scrcpy", "A", claims, "w1")?.label).toBe("main")
    expect(claimantOf("js-console", "B", claims, "main")?.label).toBe("w1")
  })

  /** This window holding it is not a conflict — it is the ordinary case. */
  it("ignores this window's own claim", () => {
    expect(claimantOf("scrcpy", "A", claims, "main")).toBeNull()
  })

  it("says nothing when the other window is on a different device", () => {
    expect(claimantOf("scrcpy", "B", claims, "w1")).toBeNull()
  })

  it("says nothing for a feature that duplicates fine", () => {
    expect(claimantOf("logcat", "A", claims, "w1")).toBeNull()
  })

  it("says nothing with no device selected", () => {
    expect(claimantOf("scrcpy", null, claims, "w1")).toBeNull()
  })
})

describe("windowHolding", () => {
  const claims = [
    claim({ label: "main", ordinal: 1, serial: "A" }),
    claim({ label: "w1", ordinal: 2, serial: "B" }),
  ]

  it("names the other window pointed at that device", () => {
    expect(windowHolding("B", claims, "main")?.label).toBe("w1")
  })

  it("does not count this window", () => {
    expect(windowHolding("A", claims, "main")).toBeNull()
  })

  it("says nothing for a device nobody has selected", () => {
    expect(windowHolding("C", claims, "main")).toBeNull()
  })
})

describe("windowTint", () => {
  /**
   * One window has to look exactly as it always did, which is why the first is
   * untinted and keeps the app accent — the Mac's `DeviceTint` rule.
   */
  it("leaves the first window alone and tints the rest", () => {
    expect(windowTint(1)).toBeNull()
    expect(windowTint(2)).not.toBeNull()
    expect(windowTint(3)).not.toBeNull()
    expect(windowTint(2)).not.toBe(windowTint(3))
  })

  it("wraps rather than running out", () => {
    expect(windowTint(20)).not.toBeNull()
  })

  it("treats a zero or negative ordinal as the first window", () => {
    expect(windowTint(0)).toBeNull()
  })
})

describe("windowTitle", () => {
  it("names a window by its number", () => {
    expect(windowTitle(2)).toBe("Window 2")
  })
})

describe("hasOtherWindows", () => {
  /**
   * With one window the app must look untouched — no Windows section, no tint,
   * no banners. That is the ordinary case and the one people see most.
   */
  it("is false for a single window, and for none at all", () => {
    expect(hasOtherWindows([claim({ label: "main" })], "main")).toBe(false)
    expect(hasOtherWindows([], "main")).toBe(false)
  })

  it("is true once a second window exists", () => {
    expect(hasOtherWindows([claim({ label: "main" }), claim({ label: "w1" })], "main")).toBe(true)
  })
})

describe("selfClaim", () => {
  it("finds this window's own row, and nothing before it has published", () => {
    const claims = [claim({ label: "main", ordinal: 1 }), claim({ label: "w1", ordinal: 2 })]
    expect(selfClaim(claims, "w1")?.ordinal).toBe(2)
    expect(selfClaim(claims, "w9")).toBeNull()
  })
})

describe("the exclusive list", () => {
  /** Every id has to be a real feature, or a banner names something that does
   * not exist. The Mac asserts the same thing against its registry. */
  it("holds no duplicates", () => {
    expect(new Set(EXCLUSIVE_FEATURE_IDS).size).toBe(EXCLUSIVE_FEATURE_IDS.length)
  })
})
