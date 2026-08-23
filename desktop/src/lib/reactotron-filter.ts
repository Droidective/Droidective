/**
 * What the timeline shows: the hide-what-you-untick kind toggles, the API
 * method and status refinements nested under them, and the search box.
 *
 * A port of the Mac's `filteredItems` and the state behind its Timeline Filter
 * sheet. Hiding rather than showing is upstream Reactotron's model and the
 * Mac's: an *empty* hidden set shows everything, so a filter nobody has touched
 * needs no persisted default and a kind added later is visible without a
 * migration.
 */

import type { EventKind } from "@/lib/reactotron-rows"
import { rowKind, type TimelineRow } from "@/lib/reactotron-rows"

/**
 * An HTTP status bucket. `failure` is status 0 — how a request that never got a
 * response (a network error) arrives from the Reactotron client.
 */
export const STATUS_CLASSES = [0, 2, 3, 4, 5] as const
export type StatusClass = (typeof STATUS_CLASSES)[number]

export function statusLabel(status: StatusClass): string {
  return status === 0 ? "Failed" : `${status}xx`
}

/** The bucket a concrete code falls in; null for 1xx and for nonsense. */
export function statusClass(status: number): StatusClass | null {
  if (status < 0) return null
  const bucket = Math.trunc(status / 100)
  return STATUS_CLASSES.includes(bucket as StatusClass) ? (bucket as StatusClass) : null
}

/** Green for 2xx, amber for a client error, red for a server error. */
export type StatusTone = "ok" | "warn" | "error" | "neutral"

/**
 * Only the code is toned. Colouring the whole row would drown the timeline's own
 * badge colours, which is the thing a reader scans by.
 */
export function statusTone(status: number): StatusTone {
  switch (statusClass(status)) {
    case 2:
      return "ok"
    case 4:
      return "warn"
    case 5:
      return "error"
    default:
      return "neutral"
  }
}

export interface TimelineFilter {
  /** Kinds to hide. Empty shows everything. */
  hiddenKinds: readonly EventKind[]
  /** Show only API rows with this method. Null means every method. */
  method: string | null
  /** Show only API rows in this bucket. Null means every status. */
  status: StatusClass | null
  search: string
}

export function emptyFilter(): TimelineFilter {
  return { hiddenKinds: [], method: null, status: null, search: "" }
}

/** True when the filter is doing anything, for the toolbar's active dot. */
export function isFiltering(filter: TimelineFilter): boolean {
  return filter.hiddenKinds.length > 0 || filter.method !== null || filter.status !== null
}

/**
 * The rows a filter leaves visible.
 *
 * The kind set and the query are prepared once here rather than per row: on a
 * streaming feed this predicate runs over the whole buffer on every flush, and
 * the row's own `searchText` is pre-lowercased so the match is a plain substring
 * check with nothing allocated.
 */
export function filterRows(
  rows: readonly TimelineRow[],
  filter: TimelineFilter,
): TimelineRow[] {
  const hidden = new Set(filter.hiddenKinds)
  const query = filter.search.trim().toLowerCase()
  return rows.filter((row) => {
    const kind = rowKind(row.event)
    if (kind !== null && hidden.has(kind)) return false
    if (filter.method !== null && apiMethod(row) !== filter.method) return false
    if (filter.status !== null) {
      const status = apiStatus(row)
      if (status === null || statusClass(status) !== filter.status) return false
    }
    return query === "" || row.searchText.includes(query)
  })
}

/** The HTTP method of an API row; null for every other row. */
export function apiMethod(row: TimelineRow): string | null {
  return row.event.kind === "apiResponse" ? row.event.method : null
}

/** The HTTP status of an API row; null for every other row. */
export function apiStatus(row: TimelineRow): number | null {
  return row.event.kind === "apiResponse" ? row.event.status : null
}

/**
 * The methods present in the buffer, for the method picker — only what the app
 * actually sent, not a canned list.
 *
 * A restored filter's method stays in the list even before such a row arrives:
 * a relaunch starts with an empty buffer, and a picker that cannot show its own
 * active selection reads as broken.
 */
export function seenMethods(rows: readonly TimelineRow[], selected: string | null): string[] {
  const methods = new Set<string>()
  for (const row of rows) {
    const method = apiMethod(row)
    if (method !== null) methods.add(method)
  }
  if (selected !== null) methods.add(selected)
  return [...methods].toSorted()
}

/**
 * The persisted form of the hidden set.
 *
 * A sorted comma-joined string, so the same selection always stores the same
 * bytes and a diff of the settings file reads. Unknown names — a kind renamed
 * or removed since — are dropped on read rather than kept as a filter nothing
 * can turn off again.
 */
export function encodeHiddenKinds(kinds: readonly EventKind[]): string {
  return kinds.toSorted().join(",")
}

export function decodeHiddenKinds(raw: string, known: readonly EventKind[]): EventKind[] {
  const valid = new Set<string>(known)
  return raw
    .split(",")
    .filter((name): name is EventKind => valid.has(name))
    .toSorted()
}
