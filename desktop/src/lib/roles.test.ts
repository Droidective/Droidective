import { describe, expect, it } from "vitest"

import { emptyLayout, type LayoutState } from "@/lib/layout"
import {
  applyEverything,
  applyRole,
  dismissRolePicker,
  roleFeatureIDs,
  type Role,
  type RoleCatalogue,
} from "@/lib/roles"
import type { FeatureKind, FeatureSummary } from "@/lib/wire"

function feature(id: string, kind: FeatureKind = "view", category = "logs"): FeatureSummary {
  return {
    id,
    title: id,
    subtitle: null,
    keywords: [],
    category,
    kind,
    implemented: true,
    needsDevice: true,
    needsBundle: false,
    isDestructive: false,
    isAbsorbedByHub: false,
    absorbedBy: null,
    supportsRunAll: false,
    fields: [],
  }
}

const features = [
  feature("logcat"),
  feature("apps", "view", "apps"),
  feature("monkey", "instantAction"),
  feature("react-native", "view", "rn"),
  feature("reactotron", "view", "rn"),
  feature("js-console", "view", "rn"),
  feature("settings", "system"),
]

const qa: Role = {
  id: "qa",
  label: "QA / Tester",
  blurb: "Capture, recording, crash hunting.",
  featureIDs: ["logcat", "monkey"],
  categoryOrder: ["logs"],
  platforms: ["android"],
}

const catalogue: RoleCatalogue = {
  roles: [qa],
  reactNativeStackIDs: ["react-native", "reactotron", "js-console"],
}

describe("roleFeatureIDs", () => {
  it("is the role's own list when React Native is not wanted", () => {
    expect(roleFeatureIDs(qa, catalogue, false)).toEqual(["logcat", "monkey"])
  })

  /**
   * The stack *leads*: a React Native QA is both, and the tools they reach for
   * first should be at the top of the sidebar rather than wherever the role
   * happened to put them.
   */
  it("puts the React Native stack in front when it is", () => {
    expect(roleFeatureIDs(qa, catalogue, true)).toEqual([
      "react-native",
      "reactotron",
      "js-console",
      "logcat",
      "monkey",
    ])
  })

  /** A role that already curates one of them must not list it twice. */
  it("does not duplicate a stack tool the role already curates", () => {
    const rn: Role = { ...qa, featureIDs: ["reactotron", "logcat"] }
    expect(roleFeatureIDs(rn, catalogue, true)).toEqual([
      "react-native",
      "js-console",
      "reactotron",
      "logcat",
    ])
  })
})

describe("applyRole", () => {
  const base: LayoutState = { ...emptyLayout(), sidebarOrder: ["apps"], categoryOrder: ["apps"] }

  /**
   * Three things change together, and they have to: curated to the role but
   * arranged by something else reads as a bug.
   */
  it("sets the order, the section order and what is off", () => {
    const next = applyRole(base, qa, catalogue, features, false)
    expect(next.sidebarOrder).toEqual(["logcat", "monkey"])
    expect(next.categoryOrder).toEqual(["logs"])
    expect(next.selectedRole).toBe("qa")
    expect(next.roleChosen).toBe(true)
    expect(next.disabledFeatures).toEqual([
      "apps",
      "react-native",
      "reactotron",
      "js-console",
    ])
  })

  /**
   * Turning off Settings or the catalog would leave no way back, which is why
   * the Mac's `effectiveEnabledIDs` unions system features in regardless.
   */
  it("never turns a system feature off", () => {
    const next = applyRole(base, qa, catalogue, features, false)
    expect(next.disabledFeatures).not.toContain("settings")
  })

  it("leaves the stack on when React Native is wanted", () => {
    const next = applyRole(base, qa, catalogue, features, true)
    expect(next.disabledFeatures).toEqual(["apps"])
  })

  /** Everything else the window remembers is untouched by a role. */
  it("does not disturb the rest of the layout", () => {
    const withPanes = { ...base, splitFraction: 0.3, favorites: ["logcat"] }
    const next = applyRole(withPanes, qa, catalogue, features, false)
    expect(next.splitFraction).toBe(0.3)
    expect(next.favorites).toEqual(["logcat"])
  })
})

describe("applyEverything", () => {
  /**
   * It clears a previous curation rather than leaving it: asking for
   * everything and getting the last role's sidebar reads as a button that did
   * nothing.
   */
  it("clears any curation and records the choice", () => {
    const curated = applyRole(emptyLayout(), qa, catalogue, features, false)
    const next = applyEverything(curated)
    expect(next.disabledFeatures).toEqual([])
    expect(next.sidebarOrder).toEqual([])
    expect(next.categoryOrder).toEqual([])
    expect(next.selectedRole).toBeNull()
    expect(next.roleChosen).toBe(true)
  })
})

describe("dismissRolePicker", () => {
  /** Seen, not curated — so skipping is not re-asked at every launch. */
  it("records the picker as seen and changes nothing else", () => {
    const next = dismissRolePicker(emptyLayout())
    expect(next.roleChosen).toBe(true)
    expect(next).toEqual({ ...emptyLayout(), roleChosen: true })
  })
})
