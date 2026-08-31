/**
 * What belongs to *this* window rather than to the app.
 *
 * The Mac splits the same way — `AppCore` holds the feature curation, the
 * favourites and the role; `AppState` holds one window's device, tabs and
 * panes — and its doc warns that getting the split wrong is silent: a
 * per-window concept written to the shared layout gets clobbered by the other
 * window, which is exactly what the terminal-resume directories once did.
 *
 * Here the two windows share a `localStorage`, so they are kept in **separate
 * keys** rather than merged into one document. That is not merely tidier: a
 * read-modify-write of one blob from two webviews loses whichever write landed
 * first, and no amount of care inside the merge fixes that.
 */

import { HOME_TAB, type LayoutState, type SavedPane } from "@/lib/layout"
import { MAIN_WINDOW } from "@/lib/workspaces"

/** One window's own arrangement. */
export interface WindowLayout {
  /** The device its bar is pointed at, remembered across launches. */
  serial: string | null
  /** One entry per open pane, left to right. */
  panes: SavedPane[]
  focusedPane: number
  /** Where the divider sits when split, as a fraction of the split area. */
  splitFraction: number
}

export function emptyWindowLayout(): WindowLayout {
  return {
    serial: null,
    panes: [{ tabs: [HOME_TAB], activeTab: HOME_TAB }],
    focusedPane: 0,
    splitFraction: 0.5,
  }
}

/** `droidective.window.main`, `droidective.window.w1`, … */
export function windowKey(label: string): string {
  return `droidective.window.${label}`
}

/**
 * This window's label, from the query string the opener put there.
 *
 * Read synchronously rather than through Tauri's API for the reason
 * `main.tsx` gives about the panel: the label is reachable asynchronously, and
 * a window that painted as the wrong workspace for a frame first would flash
 * another window's tabs.
 */
export function currentWindowLabel(search: string): string {
  const label = new URLSearchParams(search).get("w")
  return label === null || label === "" ? MAIN_WINDOW : label
}

/** The device a "New Window for Device" opener asked for, if any. */
export function requestedSerial(search: string): string | null {
  const serial = new URLSearchParams(search).get("serial")
  return serial === null || serial === "" ? null : serial
}

/**
 * Read one window's arrangement, folding in the pre-multi-window layout the
 * first time.
 *
 * The old single-workspace fields lived on the shared blob. They are adopted
 * into the *first* window only — `adoptWindows` on the Mac does the same — so
 * an existing install opens on the tabs it was closed with rather than on a
 * bare Home, and a second window does not inherit them.
 */
export function loadWindowLayout(
  storage: Pick<Storage, "getItem">,
  label: string,
  shared: LayoutState,
): WindowLayout {
  const own = read(storage, windowKey(label))
  if (own !== null) return own
  if (label !== MAIN_WINDOW) return emptyWindowLayout()
  return {
    serial: null,
    panes: shared.panes.length === 0 ? emptyWindowLayout().panes : shared.panes,
    focusedPane: shared.focusedPane,
    splitFraction: shared.splitFraction,
  }
}

export function saveWindowLayout(
  storage: Pick<Storage, "setItem">,
  label: string,
  layout: WindowLayout,
): void {
  try {
    storage.setItem(windowKey(label), JSON.stringify(layout))
  } catch {
    // A private window or a full profile. Losing where a divider sat is not
    // worth losing the window over — the same rule `saveLayout` follows.
  }
}

/**
 * Forget a window that has been closed for good.
 *
 * Without this every window ever opened would leave an entry behind, and
 * `w1`'s tabs would come back the next time a second window happened to be
 * given that label.
 */
export function forgetWindowLayout(storage: Pick<Storage, "removeItem">, label: string): void {
  try {
    storage.removeItem(windowKey(label))
  } catch {
    // As above.
  }
}

function read(storage: Pick<Storage, "getItem">, key: string): WindowLayout | null {
  let raw: string | null = null
  try {
    raw = storage.getItem(key)
  } catch {
    return null
  }
  if (raw === null) return null

  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch {
    return null
  }
  if (typeof parsed !== "object" || parsed === null) return null

  const saved = parsed as Partial<Record<keyof WindowLayout, unknown>>
  const panes = savedPanes(saved.panes)
  return {
    serial: typeof saved.serial === "string" && saved.serial !== "" ? saved.serial : null,
    panes: panes.length === 0 ? emptyWindowLayout().panes : panes,
    focusedPane: typeof saved.focusedPane === "number" ? saved.focusedPane : 0,
    splitFraction: typeof saved.splitFraction === "number" ? saved.splitFraction : 0.5,
  }
}

/** The same validation `layout.ts` gives its panes: a tabless pane is dropped. */
function savedPanes(value: unknown): SavedPane[] {
  if (!Array.isArray(value)) return []
  const panes: SavedPane[] = []
  for (const entry of value) {
    if (typeof entry !== "object" || entry === null) continue
    const pane = entry as Partial<Record<keyof SavedPane, unknown>>
    const tabs = Array.isArray(pane.tabs)
      ? pane.tabs.filter((tab): tab is string => typeof tab === "string")
      : []
    if (tabs.length === 0) continue
    panes.push({ tabs, activeTab: typeof pane.activeTab === "string" ? pane.activeTab : null })
  }
  return panes
}
