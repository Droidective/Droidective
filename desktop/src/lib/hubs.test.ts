/**
 * The per-hub folding rule, against the real registry.
 *
 * The rule is easy to get wrong in a way nothing else catches: hide every
 * `isAbsorbedByHub` feature the way the Mac does, and the eleven members whose
 * hub this app has *not* built vanish with no way to reach them. So these tests
 * are mostly about what must stay visible.
 */

import { describe, expect, it } from "vitest"

import { APK_STUDIO_ID, STUDIO_TABS } from "@/lib/apk-studio"
import { IMPLEMENTED_HUBS, isFoldedIntoHub, membersOf, withoutHubMembers } from "@/lib/hubs"
import { sidebarFeatures } from "@/lib/sidebar"
import { paletteResults } from "@/lib/palette"
import raw from "@/lib/__fixtures__/features.json"
import type { FeatureSummary } from "@/lib/wire"

const FEATURES = (raw as { features: FeatureSummary[] }).features

describe("isFoldedIntoHub", () => {
  it("folds a member whose hub this app has", () => {
    expect(isFoldedIntoHub({ absorbedBy: "apk-studio" })).toBe(true)
  })

  it("keeps a member whose hub this app has not built", () => {
    // The whole reason the daemon sends the id and not just the flag: hiding
    // App Info would strand it, because this app's Apps explorer has no detail
    // pane to fold it into the way the Mac's does.
    expect(isFoldedIntoHub({ absorbedBy: "apps" })).toBe(false)
  })

  it("folds a member of each hub this app has built", () => {
    for (const hub of ["react-native", "simulate", "connection"]) {
      expect(isFoldedIntoHub({ absorbedBy: hub }), `${hub} should fold`).toBe(true)
    }
  })

  it("keeps a feature no hub absorbed", () => {
    expect(isFoldedIntoHub({})).toBe(false)
    expect(isFoldedIntoHub({ absorbedBy: null })).toBe(false)
  })
})

describe("against the registry", () => {
  it("the fixture really does carry hub ids", () => {
    // Without this the filters below would pass by doing nothing.
    const absorbed = FEATURES.filter((feature) => feature.isAbsorbedByHub)
    expect(absorbed.length).toBeGreaterThan(0)
    for (const feature of absorbed) {
      expect(feature.absorbedBy, `${feature.id} is absorbed but names no hub`).toBeTruthy()
    }
  })

  it("hides exactly APK Studio's three members from the sidebar", () => {
    const shown = new Set(sidebarFeatures(FEATURES).map((feature) => feature.id))
    for (const tab of STUDIO_TABS) {
      expect(shown.has(tab.featureID), `${tab.featureID} should fold into the studio`).toBe(false)
    }
    expect(shown.has(APK_STUDIO_ID)).toBe(true)
  })

  it("keeps every member of a hub this app has not built", () => {
    const shown = new Set(sidebarFeatures(FEATURES).map((feature) => feature.id))
    const stranded = FEATURES.filter(
      (feature) =>
        feature.implemented &&
        feature.absorbedBy !== null &&
        feature.absorbedBy !== undefined &&
        !IMPLEMENTED_HUBS.has(feature.absorbedBy) &&
        !shown.has(feature.id),
    )
    expect(stranded.map((feature) => feature.id)).toEqual([])
  })

  it("keeps the studio's members out of the palette too", () => {
    const shown = new Set(paletteResults(FEATURES, "", []).map((feature) => feature.id))
    for (const tab of STUDIO_TABS) expect(shown.has(tab.featureID)).toBe(false)
  })

  /**
   * Discoverability, which is what makes the hiding acceptable: the Mac folds
   * each member's keywords into its hub, so searching for the member's own word
   * still lands somewhere useful.
   */
  it("still finds the studio by each folded tool's own word", () => {
    for (const word of ["decompile", "sign", "inspect"]) {
      const ids = paletteResults(FEATURES, word, []).map((feature) => feature.id)
      expect(ids, `searching "${word}" should reach APK Studio`).toContain(APK_STUDIO_ID)
    }
  })

  it("names three tabs, and they are the three the registry folds in", () => {
    const folded = membersOf(FEATURES, APK_STUDIO_ID).map((feature) => feature.id)
    expect(folded.toSorted()).toEqual(STUDIO_TABS.map((tab) => tab.featureID).toSorted())
  })

  /**
   * A hub in the set with no pane would hide its members behind a screen that
   * does not exist — the exact failure the set is there to prevent.
   */
  it("every hub claimed as implemented is a real feature", () => {
    const ids = new Set(FEATURES.map((feature) => feature.id))
    for (const hub of IMPLEMENTED_HUBS) expect(ids.has(hub), `${hub} is not a feature`).toBe(true)
  })

  it("every hub claimed as implemented actually absorbs something", () => {
    for (const hub of IMPLEMENTED_HUBS) {
      expect(membersOf(FEATURES, hub).length, `${hub} folds in nothing`).toBeGreaterThan(0)
    }
  })
})

describe("withoutHubMembers", () => {
  it("does not disturb a list with nothing folded", () => {
    const list = [{ id: "a" }, { id: "b", absorbedBy: null }]
    expect(withoutHubMembers(list)).toEqual(list)
  })

  it("answers an empty list unchanged", () => {
    expect(withoutHubMembers([])).toEqual([])
  })
})
