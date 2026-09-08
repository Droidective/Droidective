import { moveBefore, moveToEnd } from "@/lib/ordering"
import { clampedTarget } from "@/lib/pinning"

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
 *
 * Pinned tabs are the first `pinnedCount` of `openTabs` (see `lib/pinning`), so
 * every operation here either maintains that count or leaves the prefix alone.
 */
export interface TabState {
  readonly openTabs: readonly string[]
  /** Always one of `openTabs`; null only when none are open. */
  readonly activeTab: string | null
  /** How many of the leading tabs are pinned. Always `0…openTabs.length`. */
  readonly pinnedCount: number
}

/**
 * Build a state, normalising `activeTab` onto an open tab so a stale persisted
 * value cannot point at a tab that is not there.
 */
export function tabState(
  openTabs: readonly string[],
  activeTab: string | null = null,
  pinnedCount = 0,
): TabState {
  const tabs = [...openTabs]
  const active = activeTab !== null && tabs.includes(activeTab) ? activeTab : (tabs[0] ?? null)
  return {
    openTabs: tabs,
    activeTab: active,
    pinnedCount: Math.min(Math.max(pinnedCount, 0), tabs.length),
  }
}

/** The pinned tabs, in strip order — what the strip marks and what is saved. */
export function pinnedTabs(state: TabState): string[] {
  return state.openTabs.slice(0, state.pinnedCount)
}

export function isPinned(state: TabState, id: string): boolean {
  const at = state.openTabs.indexOf(id)
  return at !== -1 && at < state.pinnedCount
}

/**
 * Pin `id`: it joins the end of the pinned prefix. A no-op when it is not open
 * or is pinned already.
 */
export function pinTab(state: TabState, id: string): TabState {
  const from = state.openTabs.indexOf(id)
  if (from === -1 || from < state.pinnedCount) return state
  const openTabs = state.openTabs.filter((tab) => tab !== id)
  openTabs.splice(state.pinnedCount, 0, id)
  return { openTabs, activeTab: state.activeTab, pinnedCount: state.pinnedCount + 1 }
}

/**
 * Unpin `id`: it drops to the front of the unpinned tabs.
 *
 * Not back where it was before it was pinned — `pinTab` does not record that,
 * and remembering it would be state that goes stale the moment a neighbouring
 * tab closes. The boundary is where the eye last saw the tab anyway.
 */
export function unpinTab(state: TabState, id: string): TabState {
  const from = state.openTabs.indexOf(id)
  if (from === -1 || from >= state.pinnedCount) return state
  const openTabs = state.openTabs.filter((tab) => tab !== id)
  openTabs.splice(state.pinnedCount - 1, 0, id)
  return { openTabs, activeTab: state.activeTab, pinnedCount: state.pinnedCount - 1 }
}

/** Open `id`, or refocus it when it is already open. */
export function openTab(state: TabState, id: string): TabState {
  return {
    openTabs: state.openTabs.includes(id) ? state.openTabs : [...state.openTabs, id],
    activeTab: id,
    pinnedCount: state.pinnedCount,
  }
}

/**
 * Close `id`.
 *
 * If it held focus, the neighbour that slid into its slot takes it — its old
 * right neighbour, or the new last tab when the rightmost closed. A pane can be
 * left empty: what to do about that is the workspace's decision, not this one's
 * — the same division `TabState` and `Workspace` keep on the Mac.
 */
export function closeTab(state: TabState, id: string): TabState {
  const index = state.openTabs.indexOf(id)
  if (index === -1) return state
  const openTabs = state.openTabs.filter((tab) => tab !== id)
  const pinnedCount = index < state.pinnedCount ? state.pinnedCount - 1 : state.pinnedCount
  if (state.activeTab !== id) return { openTabs, activeTab: state.activeTab, pinnedCount }
  return {
    openTabs,
    activeTab: openTabs[Math.min(index, openTabs.length - 1)] ?? null,
    pinnedCount,
  }
}

/**
 * The tabs "Close Other Tabs" acts on: everything in the pane but `id`, the
 * pinned ones — being spared a bulk close is half of what pinning is for — and
 * the permanent `keep`, which rides its own button rather than a chip.
 */
export function closableTabs(state: TabState, id: string, keep: string): string[] {
  return state.openTabs.filter(
    (tab) => tab !== id && tab !== keep && !isPinned(state, tab),
  )
}

/** Close everything in the pane except `id`, `keep`, and the pinned tabs. */
export function closeOtherTabs(state: TabState, id: string, keep: string): TabState {
  const closing = new Set(closableTabs(state, id, keep))
  // Every pinned tab is spared, so the prefix survives whole and its count
  // with it.
  const kept = state.openTabs.filter((tab) => !closing.has(tab))
  return tabState(kept, id, state.pinnedCount)
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
  return {
    openTabs: state.openTabs,
    activeTab: state.openTabs[(current + offset + count) % count] ?? null,
    pinnedCount: state.pinnedCount,
  }
}

/** Activate the tab at a 0-based index (⌘1–⌘9). Out of range does nothing. */
export function activateIndex(state: TabState, index: number): TabState {
  const target = state.openTabs[index]
  return target === undefined
    ? state
    : { openTabs: state.openTabs, activeTab: target, pinnedCount: state.pinnedCount }
}

/**
 * Drop `id` before `target` (null = the end of the strip), keeping focus where
 * it is.
 *
 * Clamped to `id`'s own region: a reorder may never interleave pinned and
 * unpinned tabs, so a drop aimed across the boundary lands *at* it.
 */
export function reorderTabs(state: TabState, id: string, target: string | null): TabState {
  if (!state.openTabs.includes(id)) return state
  const clamped = clampedTarget(id, target, state.openTabs, state.pinnedCount)
  const openTabs =
    clamped === null ? moveToEnd(id, state.openTabs) : moveBefore(id, clamped, state.openTabs)
  return { openTabs, activeTab: state.activeTab, pinnedCount: state.pinnedCount }
}
