import { dropTarget } from "@/lib/ordering"

/**
 * The pinned-prefix rules for a tab strip, ported from ADBKit's `TabPinning`.
 *
 * A pane's pinned tabs are exactly the first `pinnedCount` of its open tabs —
 * pinning is a *position*, not a parallel set, so the two can never disagree
 * about which tabs are pinned or what order they sit in. Everything that
 * rearranges tabs has to keep that prefix intact, which is what the two
 * functions here are for: `normalizePinned` establishes it from persisted data,
 * and `clampedTarget` stops a drag-reorder breaking it.
 */

/**
 * Partition `tabs` so the pinned ones lead, keeping the relative order within
 * each region, and report how many there are.
 *
 * The persisted form is a list of ids rather than a count, because a restore
 * drops tabs whose feature is gone and a count would then point at whatever
 * slid into their place.
 */
export function normalizePinned(
  tabs: readonly string[],
  pinned: ReadonlySet<string>,
): { tabs: string[]; pinnedCount: number } {
  const front = tabs.filter((id) => pinned.has(id))
  const rest = tabs.filter((id) => !pinned.has(id))
  return { tabs: [...front, ...rest], pinnedCount: front.length }
}

/**
 * The insertion target a reorder may actually use.
 *
 * A drop that would land an unpinned tab inside the pinned prefix — or a pinned
 * tab past it — is pulled back to the boundary, the way Chrome stops the drag
 * there rather than silently reordering somewhere else. `target` is the id the
 * tab should sit before, null for the end of the strip; the result has the same
 * meaning.
 *
 * A tab that is not in `tabs` (a drag from another pane, still to arrive) keeps
 * its target: it has no region here yet.
 */
export function clampedTarget(
  id: string,
  target: string | null,
  tabs: readonly string[],
  pinnedCount: number,
): string | null {
  const from = tabs.indexOf(id)
  if (from === -1) return target
  // Where `moveBefore` would put it: removing the tab first shifts a target
  // that sat to its right one slot left, and an absent target means the end.
  const to = target === null ? -1 : tabs.indexOf(target)
  const landing = to === -1 ? tabs.length - 1 : to > from ? to - 1 : to
  const isPinned = from < pinnedCount
  const staysInRegion = isPinned ? landing < pinnedCount : landing >= pinnedCount
  if (staysInRegion) return target
  // The boundary, from either side: the first unpinned tab. With nothing
  // unpinned there is no boundary to stop at and the end is the prefix.
  return tabs[pinnedCount] ?? null
}

/**
 * Where a drop on a chip lands: the id to insert the dragged tab before, null
 * for the end of the strip.
 *
 * `chips` is what the strip *renders*, not what the pane holds — a permanent
 * tab that rides its own button is in the pane and is not a chip, and clamping
 * against the pane could name it as the boundary, leaving the marker on a chip
 * nobody drew. It is never pinned, so leaving it out keeps the prefix intact.
 */
export function dropLanding(
  dragged: string,
  target: string,
  after: boolean,
  chips: readonly string[],
  pinnedCount: number,
): string | null {
  return clampedTarget(dragged, dropTarget(target, after, chips), chips, pinnedCount)
}

/**
 * Where the strip's insertion marker goes for a hover, given that landing.
 *
 * null draws nothing: either the strip has no chips, or the landing is the
 * dragged tab itself, which means it would not move.
 */
export function markerSlot(
  dragged: string,
  landing: string | null,
  chips: readonly string[],
): { id: string; after: boolean } | null {
  if (landing === null) {
    const last = chips.at(-1)
    return last === undefined ? null : { id: last, after: true }
  }
  return landing === dragged ? null : { id: landing, after: false }
}
