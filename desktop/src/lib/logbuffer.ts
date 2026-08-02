import type { LogLine } from "@/lib/wire"

/**
 * The logcat feed's backing store.
 *
 * Pure and immutable so the trimming and gap rules are tested without a
 * device, a socket, or a rendered list — the same reason ADBKit keeps its
 * parsers static.
 */

export type LogRow =
  | { kind: "line"; key: number; line: LogLine }
  /** A visible stand-in for what the daemon's bounded buffer discarded. */
  | { kind: "gap"; key: number; count: number }

export interface LogBuffer {
  rows: LogRow[]
  /** Monotonic, so React keys stay stable across a trim. */
  nextKey: number
  /** Everything the daemon has told us it dropped, for the status line. */
  dropped: number
}

/**
 * Deliberately finite. Android's own logcat ring drops under load, so an
 * unbounded UI buffer buys nothing but memory — and the daemon already
 * decided that a responsive feed with an honest gap beats a complete one.
 */
export const LOG_CAPACITY = 5000

export function emptyBuffer(): LogBuffer {
  return { rows: [], nextKey: 0, dropped: 0 }
}

export function withLines(
  buffer: LogBuffer,
  lines: LogLine[],
  capacity: number = LOG_CAPACITY,
): LogBuffer {
  if (lines.length === 0) return buffer
  let nextKey = buffer.nextKey
  const appended: LogRow[] = lines.map((line) => ({ kind: "line", key: nextKey++, line }))
  return trim({ rows: [...buffer.rows, ...appended], nextKey, dropped: buffer.dropped }, capacity)
}

/**
 * Records a gap. Consecutive gaps merge into one row: two `dropped` events in
 * a row are one interruption as far as a reader is concerned, and stacking
 * separate markers would bury the lines around them.
 */
export function withGap(
  buffer: LogBuffer,
  count: number,
  capacity: number = LOG_CAPACITY,
): LogBuffer {
  if (count <= 0) return buffer
  const dropped = buffer.dropped + count
  const last = buffer.rows.at(-1)
  if (last?.kind === "gap") {
    const merged: LogRow = { kind: "gap", key: last.key, count: last.count + count }
    return { rows: [...buffer.rows.slice(0, -1), merged], nextKey: buffer.nextKey, dropped }
  }
  const rows: LogRow[] = [...buffer.rows, { kind: "gap", key: buffer.nextKey, count }]
  return trim({ rows, nextKey: buffer.nextKey + 1, dropped }, capacity)
}

function trim(buffer: LogBuffer, capacity: number): LogBuffer {
  if (capacity <= 0) return { ...buffer, rows: [] }
  if (buffer.rows.length <= capacity) return buffer
  return { ...buffer, rows: buffer.rows.slice(buffer.rows.length - capacity) }
}

/** Case-insensitive substring match over the parts a reader can see. */
export function matchesFilter(row: LogRow, filter: string): boolean {
  const needle = filter.toLowerCase().trim()
  if (needle === "") return true
  // A gap always shows: hiding it would turn a visible interruption back into
  // a silent one, which is the whole thing the marker exists to prevent.
  if (row.kind === "gap") return true
  const { tag, message, level, pid } = row.line
  return `${tag} ${message} ${level} ${pid}`.toLowerCase().includes(needle)
}
