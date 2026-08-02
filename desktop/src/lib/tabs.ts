import { moveBefore, moveToEnd } from "@/lib/ordering"

/**
 * The open feature tabs and which one is active, ported from ADBKit's
 * `TabState` so both apps answer "what gets focus when I close this?" the same
 * way.
 *
 * Immutable rather than a mutating struct: every operation returns a new state,
 * which is what React wants and what lets the close/cycle rules be tested
 * without a window.
 *
 * Tabs are strictly distinct features — a feature's id *is* its tab id, so
 * opening one that is already open refocuses it instead of duplicating it.
 */
export interface TabState {
  readonly openTabs: readonly string[]
  /** Always one of `openTabs`; null only when none are open. */
  readonly activeTab: string | null
}

/**
 * Build a state, normalising `activeTab` onto an open tab so a stale persisted
 * value cannot point at a tab that is not there.
 */
export function tabState(openTabs: readonly string[], activeTab: string | null = null): TabState {
  const tabs = [...openTabs]
  const active = activeTab !== null && tabs.includes(activeTab) ? activeTab : (tabs[0] ?? null)
  return { openTabs: tabs, activeTab: active }
}

/** Open `id`, or refocus it when it is already open. */
export function openTab(state: TabState, id: string): TabState {
  return {
    openTabs: state.openTabs.includes(id) ? state.openTabs : [...state.openTabs, id],
    activeTab: id,
  }
}

/**
 * Close `id`.
 *
 * If it held focus, the neighbour that slid into its slot takes it — its old
 * right neighbour, or the new last tab when the rightmost closed. Closing the
 * last tab reseeds `fallback` rather than leaving an empty window, which is
 * what `Workspace.fallback` does on the Mac.
 */
export function closeTab(state: TabState, id: string, fallback: string): TabState {
  const index = state.openTabs.indexOf(id)
  if (index === -1) return state
  const openTabs = state.openTabs.filter((tab) => tab !== id)
  if (openTabs.length === 0) return { openTabs: [fallback], activeTab: fallback }
  if (state.activeTab !== id) return { openTabs, activeTab: state.activeTab }
  return { openTabs, activeTab: openTabs[Math.min(index, openTabs.length - 1)] ?? null }
}

/** Close everything in the strip except `id` (and the permanent `fallback`). */
export function closeOtherTabs(state: TabState, id: string, fallback: string): TabState {
  const openTabs = state.openTabs.filter((tab) => tab === id || tab === fallback)
  return tabState(openTabs, id)
}

/** Activate the next tab to the right, wrapping to the first. */
export function activateNext(state: TabState): TabState {
  return cycle(state, 1)
}

/** Activate the previous tab to the left, wrapping to the last. */
export function activatePrevious(state: TabState): TabState {
  return cycle(state, -1)
}

function cycle(state: TabState, offset: number): TabState {
  const count = state.openTabs.length
  if (count === 0) return state
  const current = state.activeTab === null ? 0 : Math.max(state.openTabs.indexOf(state.activeTab), 0)
  return { openTabs: state.openTabs, activeTab: state.openTabs[(current + offset + count) % count] ?? null }
}

/** Activate the tab at a 0-based index (⌘1–⌘9). Out of range does nothing. */
export function activateIndex(state: TabState, index: number): TabState {
  const target = state.openTabs[index]
  return target === undefined ? state : { openTabs: state.openTabs, activeTab: target }
}

/**
 * Drop `id` before `target` (null = the end of the strip), keeping focus where
 * it is. Reordering is a rearrangement, so anything that is not a permutation
 * of the open tabs is ignored.
 */
export function reorderTabs(state: TabState, id: string, target: string | null): TabState {
  if (!state.openTabs.includes(id)) return state
  const openTabs =
    target === null ? moveToEnd(id, state.openTabs) : moveBefore(id, target, state.openTabs)
  return { openTabs, activeTab: state.activeTab }
}
