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

/** Android's priorities, quietest first. The order *is* the comparison. */
export const LEVELS = ["V", "D", "I", "W", "E", "F"] as const
export type Level = (typeof LEVELS)[number]

export interface LogFilter {
  /** Hides every line that does not contain it. */
  text: string
  /** Hides everything quieter than this. */
  minLevel: Level
  /** Tag chips; a line matching any of them shows. Empty means all tags. */
  tags: readonly string[]
}

export function emptyFilter(): LogFilter {
  return { text: "", minLevel: "V", tags: [] }
}

/**
 * Whether a row survives the filter.
 *
 * A gap always shows, whatever is filtered: hiding it would turn a visible
 * interruption back into a silent one, which is the whole thing the marker
 * exists to prevent.
 */
export function matchesLogFilter(row: LogRow, filter: LogFilter): boolean {
  if (row.kind === "gap") return true
  const { tag, message, level, pid } = row.line
  if (LEVELS.indexOf(level as Level) < LEVELS.indexOf(filter.minLevel)) return false
  if (filter.tags.length > 0 && !filter.tags.includes(tag)) return false
  const needle = filter.text.toLowerCase().trim()
  if (needle === "") return true
  return `${tag} ${message} ${level} ${pid}`.toLowerCase().includes(needle)
}

/**
 * Whether a row is a Find hit.
 *
 * Find highlights without hiding, which is the split the Mac's log view keeps:
 * "where is this?" and "show me only this" are different questions, and one
 * control cannot answer both.
 */
export function matchesFind(row: LogRow, find: string): boolean {
  const needle = find.toLowerCase().trim()
  if (needle === "" || row.kind === "gap") return false
  const { tag, message } = row.line
  return `${tag} ${message}`.toLowerCase().includes(needle)
}

/** The visible rows as text, for export or the clipboard. */
export function logText(rows: readonly LogRow[]): string {
  return rows
    .map((row) =>
      row.kind === "gap"
        ? `--- ${row.count.toLocaleString()} lines dropped ---`
        : `${row.line.time} ${row.line.pid} ${row.line.level}/${row.line.tag}: ${row.line.message}`,
    )
    .join("\n")
}

/** Every tag present, most frequent first — what the tag chips offer. */
export function tagsByFrequency(rows: readonly LogRow[]): string[] {
  const counts = new Map<string, number>()
  for (const row of rows) {
    if (row.kind !== "line") continue
    counts.set(row.line.tag, (counts.get(row.line.tag) ?? 0) + 1)
  }
  return [...counts.entries()]
    .toSorted((a, b) => (b[1] === a[1] ? a[0].localeCompare(b[0]) : b[1] - a[1]))
    .map(([tag]) => tag)
}
