/**
 * Which hub screens this UI has actually built.
 *
 * The Mac folds eleven features into four hubs and hides every member from its
 * sidebar, catalog and search, because it has all four screens. This app has
 * one of them. That is the whole reason the daemon sends `absorbedBy` rather
 * than only the flag: hiding a member whose hub does not exist here would
 * strand the feature with no way to reach it at all.
 *
 * So the rule is *per hub*, not per member. Add an id here in the same change
 * that adds its pane, and the members fold in on their own — that is what
 * `hubsAreRealPanes` in the test checks, and what keeps a half-built hub from
 * hiding features behind a screen nobody can open.
 */

import type { FeatureSummary } from "@/lib/wire"

/** Hub ids with a real pane in this app. */
export const IMPLEMENTED_HUBS: ReadonlySet<string> = new Set(["apk-studio"])

/**
 * Whether a feature should be hidden from the sidebar, catalog and search
 * because the hub that owns it is on screen here.
 *
 * A member whose hub is not built stays standalone — visible, openable, and
 * exactly where it was.
 */
export function isFoldedIntoHub(feature: {
  absorbedBy?: string | null
}): boolean {
  const hub = feature.absorbedBy
  if (hub === null || hub === undefined) return false
  return IMPLEMENTED_HUBS.has(hub)
}

/** Everything a list should show, with folded-away members removed. */
export function withoutHubMembers<T extends { absorbedBy?: string | null }>(
  features: readonly T[],
): T[] {
  return features.filter((feature) => !isFoldedIntoHub(feature))
}

/**
 * The members one hub folded in, for the hub's own screen to offer.
 *
 * Order follows the list the daemon served, which is registry order — the same
 * order the Mac's hub shows them in.
 */
export function membersOf(features: readonly FeatureSummary[], hub: string): FeatureSummary[] {
  return features.filter((feature) => feature.absorbedBy === hub)
}
