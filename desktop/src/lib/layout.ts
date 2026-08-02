import { tabState, type TabState } from "@/lib/tabs"

/**
 * What the window remembers between launches: how the sidebar is arranged and
 * which tabs were open.
 *
 * The Mac keeps this in `LayoutState` under Application Support; here it is
 * `localStorage`, which the webview already has — reaching for a file would
 * mean granting the webview a filesystem capability it deliberately does not
 * have. The shapes are the same, so the fields line up if they ever need to.
 */

/** The permanent first tab, and what a closed last tab falls back to. */
export const HOME_TAB = "home"

export interface LayoutState {
  /** The user's feature order. Empty until something is actually dragged. */
  sidebarOrder: string[]
  categoryOrder: string[]
  collapsedCategories: string[]
  openTabs: string[]
  activeTab: string | null
}

const STORAGE_KEY = "droidective.layout"

export function emptyLayout(): LayoutState {
  return {
    sidebarOrder: [],
    categoryOrder: [],
    collapsedCategories: [],
    openTabs: [HOME_TAB],
    activeTab: HOME_TAB,
  }
}

/**
 * Read the saved layout, falling back to the default for anything malformed.
 *
 * Every field is validated rather than trusted: this is persisted JSON that a
 * previous version wrote, and a shape that has since changed must not take the
 * window down with it. The Mac's `JSONStore` sets a corrupt file aside for the
 * same reason.
 */
export function loadLayout(storage: Pick<Storage, "getItem">): LayoutState {
  const raw = storage.getItem(STORAGE_KEY)
  if (raw === null) return emptyLayout()
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch {
    return emptyLayout()
  }
  if (typeof parsed !== "object" || parsed === null) return emptyLayout()
  const saved = parsed as Partial<Record<keyof LayoutState, unknown>>
  const openTabs = stringArray(saved.openTabs)
  const activeTab = typeof saved.activeTab === "string" ? saved.activeTab : null
  return {
    sidebarOrder: stringArray(saved.sidebarOrder),
    categoryOrder: stringArray(saved.categoryOrder),
    collapsedCategories: stringArray(saved.collapsedCategories),
    openTabs: openTabs.length === 0 ? [HOME_TAB] : openTabs,
    activeTab,
  }
}

/**
 * Write the layout. A failure is swallowed on purpose — `localStorage` throws
 * when a webview is running in private mode or over quota, and losing the
 * arrangement of a sidebar is not worth losing the window over.
 */
export function saveLayout(storage: Pick<Storage, "setItem">, layout: LayoutState): void {
  try {
    storage.setItem(STORAGE_KEY, JSON.stringify(layout))
  } catch {
    // Nothing useful to do, and nothing that should reach the user.
  }
}

/**
 * The tab strip a saved layout restores to.
 *
 * A persisted id is only opened if it still names a feature this build has:
 * one that was removed, or renamed, would otherwise come back as a tab that
 * renders nothing. Home always leads the strip, whatever was saved.
 */
export function restoreTabs(layout: LayoutState, isKnownTab: (id: string) => boolean): TabState {
  const restored = layout.openTabs.filter((id) => id !== HOME_TAB && isKnownTab(id))
  return tabState([HOME_TAB, ...restored], layout.activeTab)
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.filter((entry): entry is string => typeof entry === "string")
}
