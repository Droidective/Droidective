import { restoreWorkspace, type Workspace } from "@/lib/workspace"

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

/** One pane's worth of saved tabs. */
export interface SavedPane {
  tabs: string[]
  activeTab: string | null
}

export interface LayoutState {
  /** The user's feature order. Empty until something is actually dragged. */
  sidebarOrder: string[]
  categoryOrder: string[]
  collapsedCategories: string[]
  /** Pinned feature ids, in the order they were pinned. */
  favorites: string[]
  /** One entry per open pane, left to right. */
  panes: SavedPane[]
  focusedPane: number
  /** Where the divider sits when split, as a fraction of the split area. */
  splitFraction: number
}

const STORAGE_KEY = "droidective.layout"

export function emptyLayout(): LayoutState {
  return {
    sidebarOrder: [],
    categoryOrder: [],
    collapsedCategories: [],
    favorites: [],
    panes: [{ tabs: [HOME_TAB], activeTab: HOME_TAB }],
    focusedPane: 0,
    splitFraction: 0.5,
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
  const panes = savedPanes(saved.panes)
  return {
    sidebarOrder: stringArray(saved.sidebarOrder),
    categoryOrder: stringArray(saved.categoryOrder),
    collapsedCategories: stringArray(saved.collapsedCategories),
    favorites: stringArray(saved.favorites),
    panes: panes.length === 0 ? emptyLayout().panes : panes,
    focusedPane: typeof saved.focusedPane === "number" ? saved.focusedPane : 0,
    splitFraction: typeof saved.splitFraction === "number" ? saved.splitFraction : 0.5,
  }
}

function savedPanes(value: unknown): SavedPane[] {
  if (!Array.isArray(value)) return []
  const panes: SavedPane[] = []
  for (const entry of value) {
    if (typeof entry !== "object" || entry === null) continue
    const pane = entry as Partial<Record<keyof SavedPane, unknown>>
    const tabs = stringArray(pane.tabs)
    if (tabs.length === 0) continue
    panes.push({ tabs, activeTab: typeof pane.activeTab === "string" ? pane.activeTab : null })
  }
  return panes
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
 * The workspace a saved layout restores to.
 *
 * A persisted id is only reopened if it still names a feature this build has:
 * one that was removed, or renamed, would otherwise come back as a tab that
 * renders nothing. Home always leads the first pane, whatever was saved — it is
 * where a closed last tab lands, so it cannot be missing.
 */
export function restoreWorkspaceFrom(
  layout: LayoutState,
  isKnownTab: (id: string) => boolean,
): Workspace {
  const panes = layout.panes.map((pane, index) => ({
    tabs: index === 0 ? [HOME_TAB, ...pane.tabs.filter((id) => id !== HOME_TAB)] : pane.tabs,
    activeTab: pane.activeTab,
  }))
  return restoreWorkspace(panes, layout.focusedPane, HOME_TAB, (id) => id === HOME_TAB || isKnownTab(id))
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.filter((entry): entry is string => typeof entry === "string")
}
