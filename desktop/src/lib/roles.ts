import { canDisable } from "@/lib/catalog"
import type { LayoutState } from "@/lib/layout"
import type { FeatureSummary } from "@/lib/wire"

/**
 * Curating the sidebar to a role — the Mac's `LayoutState.seedRole`.
 *
 * The role's feature list is *served* rather than listed here (the daemon's
 * `/v1/features/roles`, from `FeatureRegistry.featuresByRole`): a second copy
 * in TypeScript would drift the first time a feature joined a role, and
 * nothing would fail to say so. What this file owns is what a role does to
 * *this* layout, which is where the two apps genuinely differ — the Mac stores
 * the enabled set, and this stores the disabled one, because everything here
 * is on by default.
 */

/** One role, as `/v1/features/roles` serves it. */
export interface Role {
  id: string
  label: string
  blurb: string
  featureIDs: string[]
  categoryOrder: string[]
  platforms: string[]
}

export interface RoleCatalogue {
  roles: Role[]
  /** What "I work with React Native" adds to whichever role is chosen. */
  reactNativeStackIDs: string[]
}

/**
 * The features a role turns on, with the React Native stack folded in.
 *
 * The stack *leads*, as it does on the Mac: a React Native QA is both, and the
 * tools they reach for first should be at the top of the sidebar rather than
 * wherever the role happened to put them.
 */
export function roleFeatureIDs(
  role: Role,
  catalogue: RoleCatalogue,
  includeReactNative: boolean,
): string[] {
  if (!includeReactNative) return role.featureIDs
  const added = catalogue.reactNativeStackIDs.filter((id) => !role.featureIDs.includes(id))
  return [...added, ...role.featureIDs]
}

/**
 * Curate a layout to a role.
 *
 * Three things change together, and they have to: the sidebar lists the role's
 * features, in the role's order, grouped in the role's section order. Setting
 * one without the others gives a sidebar curated to the role but arranged by
 * something else, which reads as a bug.
 *
 * System features are never disabled — `canDisable` is the same rule the
 * catalog screen uses, and the Mac's `effectiveEnabledIDs` unions them back in
 * whatever the stored set says, because turning off Settings or the catalog
 * would leave no way back.
 */
export function applyRole(
  layout: LayoutState,
  role: Role,
  catalogue: RoleCatalogue,
  features: readonly FeatureSummary[],
  includeReactNative: boolean,
): LayoutState {
  const wanted = new Set(roleFeatureIDs(role, catalogue, includeReactNative))
  return {
    ...layout,
    selectedRole: role.id,
    roleChosen: true,
    sidebarOrder: roleFeatureIDs(role, catalogue, includeReactNative),
    categoryOrder: role.categoryOrder,
    disabledFeatures: features
      .filter((feature) => !wanted.has(feature.id) && canDisable(feature))
      .map((feature) => feature.id),
  }
}

/**
 * The "show me everything" choice — the Mac's `seedEverything`.
 *
 * It clears a previous role's curation rather than leaving it in place with the
 * role forgotten: someone asking for everything and getting the last role's
 * sidebar would reasonably think the button did nothing.
 */
export function applyEverything(layout: LayoutState): LayoutState {
  return {
    ...layout,
    selectedRole: null,
    roleChosen: true,
    sidebarOrder: [],
    categoryOrder: [],
    disabledFeatures: [],
  }
}

/** Record that the picker has been seen without curating anything. */
export function dismissRolePicker(layout: LayoutState): LayoutState {
  return { ...layout, roleChosen: true }
}
