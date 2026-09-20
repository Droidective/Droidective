/**
 * The timeline's two panes.
 *
 * Split gives each pane its own filter and its own order over **one shared
 * buffer** — API traffic on one side, logs on the other. Nothing is duplicated:
 * a pane is a view onto the same rows, which is why clearing one is a
 * watermark rather than a delete.
 *
 * Pure, because the two rules worth getting right are invisible when they go
 * wrong. The clear boundary is *inclusive*, and closing the split forgets only
 * the right pane's clear.
 */

import { emptyFilter, filterRows, type TimelineFilter } from "@/lib/reactotron-filter"
import type { TimelineRow } from "@/lib/reactotron-rows"

export interface PaneState {
  filter: TimelineFilter
  newestFirst: boolean
  /**
   * The id of the newest row at the moment this pane was cleared, or 0.
   *
   * A watermark rather than a deletion: the buffer is shared, so removing rows
   * would empty the other pane too. The toolbar's own trash is what frees the
   * buffer for both.
   */
  clearMark: number
}

export interface PanesState {
  split: boolean
  panes: readonly [PaneState, PaneState]
}

function freshPane(): PaneState {
  return { filter: emptyFilter(), newestFirst: false, clearMark: 0 }
}

export function emptyPanes(): PanesState {
  return { split: false, panes: [freshPane(), freshPane()] }
}

/**
 * Open or close the split.
 *
 * Closing **forgets the right pane's clear**, and only the right pane's. That
 * pane is going away, so a reopened split offers the whole timeline again —
 * which is also the way back from an accidental clear. The left pane lives on
 * as the single pane, so its clear and both panes' filters stay put.
 */
export function toggleSplit(state: PanesState): PanesState {
  if (state.split) {
    return {
      split: false,
      panes: [state.panes[0], { ...state.panes[1], clearMark: 0 }],
    }
  }
  return { ...state, split: true }
}

/** Replace one pane's settings, leaving the other alone. */
export function withPane(state: PanesState, index: number, next: PaneState): PanesState {
  return {
    ...state,
    panes: index === 0 ? [next, state.panes[1]] : [state.panes[0], next],
  }
}

/**
 * Clear one pane: hide everything received so far from it, without touching
 * the other.
 *
 * The mark is the newest row's id *at this moment*, and `visibleIn` hides rows
 * up to and including it — exclusive would leak the last pre-clear row straight
 * back into the pane.
 */
export function clearPane(state: PanesState, index: number, rows: readonly TimelineRow[]): PanesState {
  const newest = rows.at(-1)?.id ?? 0
  return withPane(state, index, { ...state.panes[index === 0 ? 0 : 1], clearMark: newest })
}

/** Whether a pane is showing nothing *because it was cleared*, not because nothing arrived. */
export function clearedEmpty(state: PaneState, shown: readonly TimelineRow[]): boolean {
  return state.clearMark > 0 && shown.length === 0
}

/** What one pane shows: the shared buffer past its watermark, then its filter. */
export function visibleIn(rows: readonly TimelineRow[], state: PaneState): TimelineRow[] {
  const past = state.clearMark === 0 ? rows : rows.filter((row) => row.id > state.clearMark)
  return filterRows(past, state.filter)
}
