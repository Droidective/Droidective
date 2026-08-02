import { describe, expect, it } from "vitest"
import { actionLabel, searchApps, sortApps } from "@/lib/apps"
import type { AppSummary } from "@/lib/wire"

function app(packageId: string, overrides: Partial<AppSummary> = {}): AppSummary {
  return {
    packageId,
    displayName: packageId.split(".").at(-1) ?? packageId,
    versionName: "1.0",
    isSystem: false,
    ...overrides,
  }
}

const apps = [
  app("com.example.weather", { displayName: "Weather" }),
  app("com.android.settings", { displayName: "Settings", isSystem: true }),
  app("com.acme.banking", { displayName: "Banking", versionName: "3.4.1" }),
]

describe("searchApps", () => {
  it("hides system apps unless asked", () => {
    expect(searchApps(apps, "", false).map((each) => each.packageId)).toEqual([
      "com.example.weather",
      "com.acme.banking",
    ])
    expect(searchApps(apps, "", true)).toHaveLength(3)
  })

  it("matches the package id, the name, and the version", () => {
    expect(searchApps(apps, "acme", false).map((each) => each.displayName)).toEqual(["Banking"])
    expect(searchApps(apps, "weather", false).map((each) => each.displayName)).toEqual(["Weather"])
    expect(searchApps(apps, "3.4", false).map((each) => each.displayName)).toEqual(["Banking"])
  })

  it("is case-insensitive and ignores surrounding space", () => {
    expect(searchApps(apps, "  WEATHER  ", false)).toHaveLength(1)
  })

  it("still hides system apps that match the query", () => {
    // Otherwise typing narrows the list and system apps reappear, which reads
    // as the toggle having no effect.
    expect(searchApps(apps, "settings", false)).toEqual([])
    expect(searchApps(apps, "settings", true)).toHaveLength(1)
  })
})

describe("sortApps", () => {
  it("puts user apps before system apps, alphabetically within each", () => {
    expect(sortApps(apps).map((each) => each.displayName)).toEqual([
      "Banking",
      "Weather",
      "Settings",
    ])
  })

  it("does not mutate its input", () => {
    const original = [...apps]
    sortApps(apps)
    expect(apps).toEqual(original)
  })
})

describe("actionLabel", () => {
  it("names the verbs the daemon ships", () => {
    expect(actionLabel({ id: "clearData", isDestructive: true })).toBe("Clear Data")
    expect(actionLabel({ id: "stop", isDestructive: false })).toBe("Force Stop")
  })

  it("still renders a verb this build has never heard of", () => {
    // The daemon owns the verb list; one added later must appear rather than
    // silently disappear from the UI.
    expect(actionLabel({ id: "freezeSolid", isDestructive: false })).toBe("Freeze Solid")
  })
})
