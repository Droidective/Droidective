import { describe, expect, it } from "vitest"
import raw from "@/lib/__fixtures__/features.json"
import { coerce, initialValues, missingRequired, runFields } from "@/lib/fields"
import type { FeatureField, FeatureSummary } from "@/lib/wire"

const features = (raw as unknown as { features: FeatureSummary[] }).features

function byID(id: string): FeatureSummary {
  const feature = features.find((candidate) => candidate.id === id)
  if (!feature) throw new Error(`the fixture has no feature ${id}`)
  return feature
}

function field(featureID: string, name: string): FeatureField {
  const found = byID(featureID).fields.find((candidate) => candidate.name === name)
  if (!found) throw new Error(`${featureID} has no field ${name}`)
  return found
}

describe("initialValues", () => {
  it("uses the registry's default when there is one", () => {
    // fake-battery's slider defaults to 5, not to its minimum.
    expect(initialValues(byID("fake-battery"))["level"]).toBe(5)
  })

  it("preselects the first option of a select", () => {
    expect(initialValues(byID("locale"))["locale"]).toBe("en-US")
  })

  it("leaves a text field empty", () => {
    expect(initialValues(byID("send-text"))["text"]).toBe("")
  })
})

describe("coerce", () => {
  const level = field("fake-battery", "level")
  const text = field("send-text", "text")

  it("turns numeric input into a number", () => {
    expect(coerce(level, "42")).toBe(42)
    expect(coerce(level, "0")).toBe(0)
  })

  it("keeps a half-typed number as text rather than inventing NaN", () => {
    // Sending NaN reaches the device as garbage; sending 0 is a value nobody
    // chose. Holding the raw string lets the form stay mid-edit.
    expect(coerce(level, "")).toBe("")
    expect(coerce(level, "-")).toBe("-")
    expect(coerce(level, "1e")).toBe("1e")
  })

  it("passes text through untouched", () => {
    expect(coerce(text, "  hello world  ")).toBe("  hello world  ")
  })

  it("takes a boolean straight from a checkbox", () => {
    expect(coerce(text, true)).toBe(true)
    expect(coerce(text, false)).toBe(false)
  })
})

describe("missingRequired", () => {
  it("flags a required field left blank", () => {
    expect(missingRequired(byID("send-text"), { text: "" })).toEqual(["text"])
    expect(missingRequired(byID("send-text"), { text: "   " })).toEqual(["text"])
    expect(missingRequired(byID("send-text"), { text: "hi" })).toEqual([])
  })

  it("treats false and zero as answers, not blanks", () => {
    // fake-battery is required-slider plus required-switch, so this also
    // pins that an unticked switch counts as answered.
    const battery = byID("fake-battery")
    expect(missingRequired(battery, { level: 0, unplugged: false })).toEqual([])
  })

  it("flags a required field the form never set", () => {
    expect(missingRequired(byID("fake-battery"), { level: 50 })).toEqual(["unplugged"])
  })

  it("never flags an optional field", () => {
    const badge = byID("push-notification").fields.find((each) => each.name === "badge")
    expect(badge?.optional).toBe(true)
    expect(missingRequired(byID("push-notification"), {})).not.toContain("badge")
  })
})

describe("runFields", () => {
  it("sends a toggle's implicit `on` and nothing else", () => {
    // The convention is not declared in `fields`; the daemon's
    // aToggleActionIsDrivenByAnOnParameter test pins the other half of it.
    const darkMode = byID("dark-mode")
    expect(darkMode.fields).toEqual([])
    expect(runFields(darkMode, {}, true)).toEqual({ on: true })
    expect(runFields(darkMode, {}, false)).toEqual({ on: false })
  })

  it("omits a blank optional field instead of sending an empty string", () => {
    const push = byID("push-notification")
    const sent = runFields(push, { badge: "" }) ?? {}
    expect(sent).not.toHaveProperty("badge")
  })

  it("sends what the form filled in", () => {
    expect(runFields(byID("send-text"), { text: "hello" })).toEqual({ text: "hello" })
  })

  it("sends no fields map at all for an action with no parameters", () => {
    expect(runFields(byID("screenshot"), {})).toBeUndefined()
  })

  it("passes the selected app to a feature that needs one", () => {
    // `monkey` is the runnable action with needsBundle; without this it ran
    // with no package at all.
    const monkey = byID("monkey")
    expect(monkey.needsBundle).toBe(true)
    expect(runFields(monkey, {}, undefined, "com.x")).toMatchObject({ packageId: "com.x" })
  })

  it("passes the selected app as context to features that do not need one", () => {
    // The Mac supplies it the same way, for features like bug-report that
    // include app detail when a bundle happens to be selected.
    expect(runFields(byID("screenshot"), {}, undefined, "com.x")).toEqual({ packageId: "com.x" })
  })

  it("omits the app when none is selected", () => {
    expect(runFields(byID("screenshot"), {}, undefined, null)).toBeUndefined()
    expect(runFields(byID("screenshot"), {}, undefined, "")).toBeUndefined()
  })

  it("keeps a toggle's `on` alongside the selected app", () => {
    expect(runFields(byID("dark-mode"), {}, true, "com.x")).toEqual({
      on: true,
      packageId: "com.x",
    })
  })
})
