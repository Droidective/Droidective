/**
 * Drag-reorder math, ported from ADBKit's `SidebarOrdering`.
 *
 * Both surfaces that reorder — the sidebar (a feature within its group, a whole
 * category) and the tab strip — express a drop the same way: *put this one
 * before that one*. Keeping the math here rather than in a component is the
 * same rule ADBKit follows, and for the same reason: it is the part worth
 * testing.
 */

/**
 * Move `item` so it sits immediately before `target`. A no-op when they are the
 * same or `item` is absent; appends when `target` is absent.
 */
export function moveBefore(item: string, target: string, order: readonly string[]): string[] {
  if (item === target) return [...order]
  if (!order.includes(item)) return [...order]
  const result = order.filter((entry) => entry !== item)
  const at = result.indexOf(target)
  if (at === -1) result.push(item)
  else result.splice(at, 0, item)
  return result
}

/** Move `item` to the end. A no-op when it is absent. */
export function moveToEnd(item: string, order: readonly string[]): string[] {
  if (!order.includes(item)) return [...order]
  return [...order.filter((entry) => entry !== item), item]
}

/**
 * Turn "dropped on `target`, on its far half" into the id to insert before —
 * null meaning the end of the list.
 *
 * Dropping past a row is the same move as dropping before the row that follows
 * it, which is the only reading that lets a drag reach the last slot at all.
 */
export function dropTarget(
  target: string,
  after: boolean,
  order: readonly string[],
): string | null {
  if (!after) return target
  const index = order.indexOf(target)
  if (index === -1) return null
  return order[index + 1] ?? null
}

/**
 * The whole outcome of a drop: the order to persist, or null when the drop
 * changes nothing.
 *
 * `group` is what the user was looking at — a sidebar section, or a tab strip —
 * and resolves where "past the last row" lands. `fullOrder` is what gets
 * written, so a drop inside one sidebar group leaves every other group where it
 * was, which is what `SidebarOrdering.reorder` does on the Mac.
 */
export function applyDrop(
  dragged: string,
  target: string,
  after: boolean,
  group: readonly string[],
  fullOrder: readonly string[],
): string[] | null {
  const before = dropTarget(target, after, group)
  const moved = before === null ? afterGroup(dragged, group, fullOrder) : moveBefore(dragged, before, fullOrder)
  return sameOrder(moved, fullOrder) ? null : moved
}

/**
 * Land `dragged` past the end of its own group rather than the end of
 * everything — moving to the bottom of one sidebar section must not jump the
 * sections below it.
 */
function afterGroup(
  dragged: string,
  group: readonly string[],
  fullOrder: readonly string[],
): string[] {
  const last = group.filter((id) => id !== dragged).at(-1)
  if (last === undefined) return [...fullOrder]
  const next = fullOrder[fullOrder.indexOf(last) + 1]
  return next === undefined ? moveToEnd(dragged, fullOrder) : moveBefore(dragged, next, fullOrder)
}

function sameOrder(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((entry, index) => entry === right[index])
}

/**
 * Rank a list by a user-defined order, falling back to its existing order.
 *
 * `order` holds only what the user has actually moved, so anything missing from
 * it keeps its incoming (registry) position — the tiebreak ADBKit's
 * `AppState.ordered(_:)` applies.
 */
export function rankBy<Item>(
  items: readonly Item[],
  order: readonly string[],
  identify: (item: Item) => string,
): Item[] {
  const rank = new Map<string, number>()
  order.forEach((id, index) => {
    if (!rank.has(id)) rank.set(id, index)
  })
  return items
    .map((item, index) => ({
      item,
      index,
      rank: rank.get(identify(item)) ?? Number.MAX_SAFE_INTEGER,
    }))
    .toSorted((a, b) => (a.rank === b.rank ? a.index - b.index : a.rank - b.rank))
    .map((entry) => entry.item)
}
