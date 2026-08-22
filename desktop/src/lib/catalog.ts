/**
 * Which features the sidebar lists.
 *
 * **Everything is on by default.** The catalog is for turning things *off*, not
 * for opting in — that is the Mac's model (`defaultEnabledIDs ==
 * catalogFeatureIDs`, and no Restore button), and it is why what gets persisted
 * here is the *disabled* set rather than the enabled one: a feature shipped
 * after this layout was written is on without needing a migration to notice it.
 * The Mac reaches the same place through `adoptNewDefaults()`.
 *
 * A disabled feature leaves the sidebar but stays searchable and reachable —
 * turning something off is a decluttering choice, not a removal.
 */

import type { FeatureSummary } from "@/lib/wire"

/**
 * Whether a feature can be turned off at all.
 *
 * `system` features are the app's own chrome — Home, the catalog, About. There
 * is nothing to declutter and no way back if one vanished, so the Mac disables
 * their switch and so does this.
 */
export function canDisable(feature: FeatureSummary): boolean {
  return feature.kind !== "system"
}

export function isEnabled(id: string, disabled: readonly string[]): boolean {
  return !disabled.includes(id)
}

/** Turning one feature on or off. */
export function withEnabled(
  disabled: readonly string[],
  id: string,
  enabled: boolean,
): string[] {
  if (enabled) return disabled.filter((entry) => entry !== id)
  return disabled.includes(id) ? [...disabled] : [...disabled, id]
}

/**
 * Turning a whole category on or off — the Mac's right-click on a group header.
 *
 * `system` members are left alone rather than silently skipped-and-counted:
 * "Disable all" over a group holding one is still a meaningful action on the
 * rest of it.
 */
export function withGroupEnabled(
  disabled: readonly string[],
  members: readonly FeatureSummary[],
  enabled: boolean,
): string[] {
  let next = [...disabled]
  for (const feature of members) {
    if (!canDisable(feature)) continue
    next = withEnabled(next, feature.id, enabled)
  }
  return next
}

/**
 * Whether a group reads as on.
 *
 * True when *any* member is on, so the right-click offers "Disable all" for a
 * partly-on group — matching `isGroupEnabled`, and matching the intuition that
 * a group with something showing is a group you would want to hide.
 */
export function isGroupEnabled(
  members: readonly FeatureSummary[],
  disabled: readonly string[],
): boolean {
  return members.some((feature) => canDisable(feature) && isEnabled(feature.id, disabled))
}

/**
 * How many features are hidden right now.
 *
 * The sidebar footer says "+ N more features" instead of "Manage features"
 * when this is non-zero, which is the only reminder that anything was turned
 * off — without it, a feature someone hid months ago is simply missing.
 */
export function hiddenCount(
  features: readonly FeatureSummary[],
  disabled: readonly string[],
): number {
  return features.filter(
    (feature) => canDisable(feature) && !isEnabled(feature.id, disabled),
  ).length
}

/** The footer's label. */
export function manageFeaturesLabel(hidden: number): string {
  if (hidden <= 0) return "Manage features"
  return `+ ${String(hidden)} more feature${hidden === 1 ? "" : "s"}`
}
