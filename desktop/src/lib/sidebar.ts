import { rankBy } from "@/lib/ordering"
import { rankFeatures } from "@/lib/palette"
import type { FeatureSummary } from "@/lib/wire"

/**
 * The grouped sidebar: which features it lists, in which order, under which
 * headings — ported from `AppState+Sidebar` so the two apps show the same list
 * in the same order.
 */

/**
 * Category display order and headings, mirroring ADBKit's
 * `FeatureCategory.displayOrder` and `.label`.
 *
 * Held here rather than sent over the wire because the daemon serves features
 * in *registry* order, which is not category display order (the registry lists
 * Logs before App Management; the sidebar shows the reverse). `sidebar.test.ts`
 * asserts every category the daemon actually serves appears here, so a new one
 * shows up as a failing test rather than an unlabelled group.
 */
const CATEGORIES: readonly { readonly id: string; readonly label: string }[] = [
  { id: "input", label: "Input & Clipboard" },
  { id: "connection", label: "Connection" },
  { id: "reactNative", label: "React Native" },
  { id: "screen", label: "Screen & Capture" },
  { id: "deviceState", label: "Device State" },
  { id: "appManagement", label: "App Management" },
  { id: "logs", label: "Logs & Diagnostics" },
  { id: "toolUX", label: "Tool UX" },
]

export const CATEGORY_ORDER: readonly string[] = CATEGORIES.map((category) => category.id)

/**
 * The heading for a category. An id with no entry above is spaced out from its
 * case name ("deviceState" → "Device State") so a category added upstream reads
 * as something rather than as a raw wire value.
 */
export function categoryLabel(category: string): string {
  const known = CATEGORIES.find((entry) => entry.id === category)
  if (known) return known.label
  const spaced = category.replaceAll(/([a-z\d])([A-Z])/gu, "$1 $2")
  return spaced.charAt(0).toUpperCase() + spaced.slice(1)
}

/**
 * The features the sidebar lists: everything the engine can actually run.
 *
 * Hub members are **kept**, unlike the Mac's sidebar, which hides them because
 * a hub screen owns them. This app has no hub screens, so hiding them would
 * make them unreachable rather than merely relocated — the same call
 * `searchActions` made before it.
 */
export function sidebarFeatures(features: readonly FeatureSummary[]): FeatureSummary[] {
  return features.filter((feature) => feature.implemented)
}

export interface SidebarSection {
  category: string
  label: string
  features: FeatureSummary[]
  /** Renders its header but none of its rows. */
  collapsed: boolean
}

export interface SidebarLayout {
  query: string
  /** The user's feature order; anything missing keeps its registry position. */
  sidebarOrder: readonly string[]
  categoryOrder: readonly string[]
  collapsedCategories: readonly string[]
  /** Pinned feature ids, in the order they were pinned. */
  favorites: readonly string[]
  /**
   * Features turned off in the catalog.
   *
   * They leave the *listing* but stay findable: turning something off is a
   * decluttering choice, not a removal, and searching is how you go looking
   * for the thing you tidied away — which is why the search branch below
   * ignores this.
   */
  disabledFeatures?: readonly string[]
}

/** The pseudo-category the Pinned section uses. Never a real wire value. */
export const PINNED_SECTION = "pinned"

/**
 * The sections the sidebar renders.
 *
 * With a query, relevance takes over: sections appear in best-hit order and
 * nothing is collapsed, because searching is how you go looking for the thing
 * you tidied away. Without one, they follow the user's category order and
 * remember what was collapsed.
 */
export function sidebarSections(
  features: readonly FeatureSummary[],
  layout: SidebarLayout,
): SidebarSection[] {
  const ordered = rankBy(sidebarFeatures(features), layout.sidebarOrder, (feature) => feature.id)
  if (layout.query.trim() !== "") return searchSections(ordered, layout.query)

  const collapsed = new Set(layout.collapsedCategories)
  const sections: SidebarSection[] = []
  const off = new Set(layout.disabledFeatures ?? [])
  const listed = ordered.filter((feature) => !off.has(feature.id))

  // Pinned leads, and its members are lifted out of their categories rather
  // than listed twice — the same call the Mac's `enabledFeatures(in:)` makes.
  const pinned = layout.favorites.flatMap((id) => listed.filter((feature) => feature.id === id))
  if (pinned.length > 0) {
    sections.push({
      category: PINNED_SECTION,
      label: "Pinned",
      features: pinned,
      collapsed: collapsed.has(PINNED_SECTION),
    })
  }

  const rest = listed.filter((feature) => !layout.favorites.includes(feature.id))
  for (const category of rankBy(orderedCategoryIDs(rest), layout.categoryOrder, (id) => id)) {
    const matching = rest.filter((feature) => feature.category === category)
    if (matching.length === 0) continue
    sections.push({
      category,
      label: categoryLabel(category),
      features: matching,
      collapsed: collapsed.has(category),
    })
  }
  return sections
}

/**
 * Every category present, display order first and anything unrecognised after
 * it — so a category this build has never heard of still gets a section.
 */
function orderedCategoryIDs(features: readonly FeatureSummary[]): string[] {
  const present = new Set(features.map((feature) => feature.category))
  const known = CATEGORY_ORDER.filter((category) => present.has(category))
  const unknown = [...present].filter((category) => !CATEGORY_ORDER.includes(category))
  return [...known, ...unknown]
}

function searchSections(features: readonly FeatureSummary[], query: string): SidebarSection[] {
  const sections: SidebarSection[] = []
  for (const feature of rankFeatures(features, query)) {
    const existing = sections.find((section) => section.category === feature.category)
    if (existing) existing.features.push(feature)
    else
      sections.push({
        category: feature.category,
        label: categoryLabel(feature.category),
        features: [feature],
        collapsed: false,
      })
  }
  return sections
}

/** Every feature the sidebar is showing, top to bottom — collapsed rows excluded. */
export function visibleFeatures(sections: readonly SidebarSection[]): FeatureSummary[] {
  return sections.flatMap((section) => (section.collapsed ? [] : section.features))
}

/** Add or remove `category` from the collapsed set. */
export function toggleCollapsed(collapsed: readonly string[], category: string): string[] {
  return collapsed.includes(category)
    ? collapsed.filter((entry) => entry !== category)
    : [...collapsed, category]
}
