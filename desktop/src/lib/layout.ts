import type { Hotkey } from "@/lib/hotkeys"
import { restoreWorkspace, type Workspace } from "@/lib/workspace"
import { clampZoomStep, DEFAULT_ZOOM_STEP } from "@/lib/zoom"

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

/**
 * The app's own screens, opened from the sidebar footer rather than the
 * registry. They are tabs like any other — the Mac opens them the same way,
 * through `requestFeature("catalog")` — but no daemon serves them.
 */
export const CATALOG_TAB = "catalog"
export const ABOUT_TAB = "about"

/** Tabs this app provides itself, which a restore must therefore accept. */
export const CHROME_TABS: readonly string[] = [HOME_TAB, CATALOG_TAB, ABOUT_TAB]

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
  /**
   * Features turned *off* in the catalog.
   *
   * The disabled set rather than the enabled one, because everything is on by
   * default: a feature shipped after this was written is on without a
   * migration having to notice it. The Mac reaches the same place by storing
   * the enabled set and running `adoptNewDefaults()` over it.
   */
  disabledFeatures: string[]
  /**
   * Feature id → its keyboard shortcut.
   *
   * The Mac keeps these in `KeyboardShortcuts`' own defaults rather than in
   * `LayoutState`, because the library owns the OS registration. Nothing owns
   * them here, so they live with the rest of what the window remembers.
   */
  hotkeys: Record<string, Hotkey>
  /**
   * The device bar's Run on all switch.
   *
   * Persisted as the Mac persists it. Safe to carry across launches because
   * `effectiveRunOnAll` gates it on the focused feature supporting a fan-out,
   * so a stale `true` cannot reach a single-device action.
   */
  runOnAll: boolean
  /** Dock-style sidebar rather than a pinned one. The Mac's `sidebarAutoHide`. */
  sidebarAutoHide: boolean
  /** An index into `ZOOM_STEPS`, so the chosen size survives a relaunch. */
  zoomStep: number
  /** One entry per open pane, left to right. */
  panes: SavedPane[]
  focusedPane: number
  /** Where the divider sits when split, as a fraction of the split area. */
  splitFraction: number
  /**
   * Closing the window hides the app behind the tray instead of quitting.
   *
   * The Mac's `keepRunningInBackground`, default on — and like the Mac's it is
   * only half the condition: closing quits anyway on a desktop that gave the
   * app no tray icon, because hiding a window nobody can bring back is not a
   * mode worth having.
   */
  keepRunningInBackground: boolean
  /**
   * The features the tray lists, when the user has chosen some.
   *
   * The Mac's `LayoutState.menuBarItems`, with the same meaning for empty:
   * *not chosen*, so the pinned features are shown instead — and failing
   * those, the enabled instant actions.
   */
  trayItems: string[]
}

const STORAGE_KEY = "droidective.layout"

export function emptyLayout(): LayoutState {
  return {
    sidebarOrder: [],
    categoryOrder: [],
    collapsedCategories: [],
    favorites: [],
    disabledFeatures: [],
    hotkeys: {},
    runOnAll: false,
    sidebarAutoHide: false,
    zoomStep: DEFAULT_ZOOM_STEP,
    panes: [{ tabs: [HOME_TAB], activeTab: HOME_TAB }],
    focusedPane: 0,
    splitFraction: 0.5,
    keepRunningInBackground: true,
    trayItems: [],
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
    disabledFeatures: stringArray(saved.disabledFeatures),
    hotkeys: savedHotkeys(saved.hotkeys),
    runOnAll: saved.runOnAll === true,
    sidebarAutoHide: saved.sidebarAutoHide === true,
    // Clamped rather than trusted: a step from a build with a different number
    // of them would otherwise index off the end of the list.
    zoomStep: clampZoomStep(typeof saved.zoomStep === "number" ? saved.zoomStep : DEFAULT_ZOOM_STEP),
    panes: panes.length === 0 ? emptyLayout().panes : panes,
    focusedPane: typeof saved.focusedPane === "number" ? saved.focusedPane : 0,
    splitFraction: typeof saved.splitFraction === "number" ? saved.splitFraction : 0.5,
    // Absent means default-on, which is not what `=== true` says — this is the
    // one boolean here whose default is true.
    keepRunningInBackground: saved.keepRunningInBackground !== false,
    trayItems: stringArray(saved.trayItems),
  }
}

/**
 * The saved shortcuts, keeping only the entries that are still whole.
 *
 * A half-written binding is worse than none: a `Hotkey` missing its `code`
 * would match a `keydown` whose own code was somehow absent, so every field is
 * checked rather than cast. One bad entry drops itself and the rest survive.
 */
function savedHotkeys(value: unknown): Record<string, Hotkey> {
  if (typeof value !== "object" || value === null) return {}
  const hotkeys: Record<string, Hotkey> = {}
  for (const [id, entry] of Object.entries(value)) {
    if (typeof entry !== "object" || entry === null) continue
    const saved = entry as Partial<Record<keyof Hotkey, unknown>>
    if (typeof saved.code !== "string" || saved.code === "") continue
    hotkeys[id] = {
      code: saved.code,
      ctrl: saved.ctrl === true,
      alt: saved.alt === true,
      shift: saved.shift === true,
      meta: saved.meta === true,
    }
  }
  return hotkeys
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
  return restoreWorkspace(panes, layout.focusedPane, HOME_TAB, (id) =>
    CHROME_TABS.includes(id) || isKnownTab(id))
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.filter((entry): entry is string => typeof entry === "string")
}
