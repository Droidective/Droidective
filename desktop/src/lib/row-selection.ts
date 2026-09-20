/**
 * Picking rows out of a feed — ADBKit's `RowSelection`, ported.
 *
 * **The part that goes wrong is never the highlight, it is the anchor.** The
 * anchor is the row a range extends *from*: the last one picked deliberately,
 * never one swept over by a range. Where it sits after each gesture decides
 * what the next ⇧-click spans, and getting that wrong shows up as a selection
 * that ratchets outward instead of re-spanning, which is the kind of bug you
 * only notice on the fourth click.
 *
 * Immutable where the Mac's is a mutating struct, because this one lives in
 * React state: every operation answers a new value, and the identity check is
 * what lets a feed skip re-rendering rows that did not change.
 */

export interface RowSelection<ID> {
  ids: ReadonlySet<ID>
  /** Where a range extends from, or null when there is nothing to span. */
  anchor: ID | null
}

export function emptySelection<ID>(): RowSelection<ID> {
  return { ids: new Set<ID>(), anchor: null }
}

export function isEmpty<ID>(selection: RowSelection<ID>): boolean {
  return selection.ids.size === 0
}

/** A plain click: this row alone. */
export function replace<ID>(id: ID): RowSelection<ID> {
  return { ids: new Set([id]), anchor: id }
}

/**
 * ⌘-click: add or drop one row and leave the rest alone.
 *
 * The row becomes the anchor either way — the next ⇧-click spans from what was
 * last touched, which is what makes ⌘-then-⇧ predictable.
 */
export function toggle<ID>(selection: RowSelection<ID>, id: ID): RowSelection<ID> {
  const ids = new Set(selection.ids)
  if (ids.has(id)) ids.delete(id)
  else ids.add(id)
  return { ids, anchor: id }
}

/**
 * ⇧-click: everything from the anchor to `id` in display order.
 *
 * `additive` keeps what was already selected; otherwise the range replaces it.
 * The anchor deliberately stays put, so shift-clicking further down and then
 * back up re-spans from the same start rather than ratcheting.
 */
export function extend<ID>(
  selection: RowSelection<ID>,
  id: ID,
  order: readonly ID[],
  additive = false,
): RowSelection<ID> {
  // A row the feed does not have is a click on nothing — leave the selection
  // alone rather than inventing a range around it.
  const end = order.indexOf(id)
  if (end === -1) return selection
  // The anchor, on the other hand, can vanish under a live feed: trimmed,
  // filtered out, cleared. Then there is no span, and this is a plain click.
  const start = selection.anchor === null ? -1 : order.indexOf(selection.anchor)
  if (start === -1) return additive ? toggle(selection, id) : replace(id)
  return {
    ids: spanned(selection, order, start, end, additive),
    anchor: selection.anchor,
  }
}

/**
 * A drag: the rows between where the pointer went down and where it is now.
 *
 * Called on every move, so it recomputes the span from the drag's own start —
 * dragging back up shrinks the selection again instead of leaving a trail.
 */
export function selectRange<ID>(
  selection: RowSelection<ID>,
  from: ID,
  to: ID,
  order: readonly ID[],
  additive = false,
): RowSelection<ID> {
  const first = order.indexOf(from)
  const last = order.indexOf(to)
  if (first === -1 || last === -1) return selection
  return { ids: spanned(selection, order, first, last, additive), anchor: from }
}

/**
 * Drop rows the feed no longer has — cleared, filtered out, or trimmed by the
 * ring buffer.
 *
 * Without this the count and any copy would include events the reader cannot
 * see. Returns the same value when nothing changed, so a feed re-rendering at
 * 60 rows a second does not get a new selection object each time.
 */
export function retain<ID>(selection: RowSelection<ID>, order: readonly ID[]): RowSelection<ID> {
  const live = new Set(order)
  const stale = [...selection.ids].some((id) => !live.has(id))
  const lostAnchor = selection.anchor !== null && !live.has(selection.anchor)
  if (!stale && !lostAnchor) return selection
  return {
    ids: new Set([...selection.ids].filter((id) => live.has(id))),
    anchor: lostAnchor ? null : selection.anchor,
  }
}

/** The selected rows in display order — what a copy needs, since a set has none. */
export function ordered<ID>(selection: RowSelection<ID>, order: readonly ID[]): ID[] {
  return order.filter((id) => selection.ids.has(id))
}

function spanned<ID>(
  selection: RowSelection<ID>,
  order: readonly ID[],
  a: number,
  b: number,
  additive: boolean,
): Set<ID> {
  const span = order.slice(Math.min(a, b), Math.max(a, b) + 1)
  return additive ? new Set([...selection.ids, ...span]) : new Set(span)
}
