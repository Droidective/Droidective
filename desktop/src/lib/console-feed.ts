/**
 * The console's rows and the rules over them, away from React and the socket.
 *
 * Kept pure so the buffer's bounds and the filter can be tested without a
 * device, a Metro, or a WebSocket — which is the only way any of it gets tested
 * at all, since the transport is the webview's.
 */

import type { ConsoleApiCall, ExceptionDetails, RemoteObject } from "@/lib/cdp"
import { argumentSummary, inlineSummary } from "@/lib/console-format"

/** The levels the console groups by, in the order the filter bar shows them. */
export const LEVELS = ["verbose", "info", "warning", "error"] as const
export type Level = (typeof LEVELS)[number]

export interface ConsoleRow {
  /** Monotonic within a session; the React key. */
  id: number
  level: Level
  /** The CDP `type` — "log", "warn", "table", "dir"… kept for the row's glyph. */
  type: string
  args: RemoteObject[]
  /** The one-line text, for the filter and for copy. */
  text: string
  /** Milliseconds since the epoch, as Hermes reported it. */
  timestamp: number
  /** Where it came from, already shortened. */
  source: string | null
  /** True for a row this app wrote (a prompt echo or a notice), not the app. */
  local: boolean
}

/**
 * How many rows to keep.
 *
 * A chatty Metro can produce thousands a minute, and a console that keeps all
 * of them stops scrolling long before it runs out of memory.
 */
export const MAX_ROWS = 5000

/**
 * CDP console types → the four levels.
 *
 * `assert` is an error in Chrome and `dir`/`dirxml`/`table` are all `log`.
 * Anything unknown is info rather than dropped: a level this does not know is
 * still a line someone printed.
 */
export function levelOf(type: string): Level {
  switch (type) {
    case "error":
    case "assert":
      return "error"
    case "warning":
    case "warn":
      return "warning"
    case "debug":
    case "trace":
    case "verbose":
      return "verbose"
    default:
      return "info"
  }
}

/** The frame worth naming as a row's source: the first the app itself owns. */
export function sourceOf(call: ConsoleApiCall): string | null {
  const frames = call.stackTrace?.callFrames ?? []
  for (const frame of frames) {
    if (frame.url === "" || frame.url.includes("node_modules")) continue
    const file = frame.url.split("?")[0]?.split("/").pop() ?? ""
    if (file === "") continue
    return `${file}:${String(frame.lineNumber + 1)}`
  }
  return null
}

/** One `Runtime.consoleAPICalled` as a row. */
export function rowFromCall(id: number, call: ConsoleApiCall): ConsoleRow {
  return {
    id,
    level: levelOf(call.type),
    type: call.type,
    args: call.args,
    text: argumentSummary(call.args),
    timestamp: call.timestamp,
    source: sourceOf(call),
    local: false,
  }
}

/** One `Runtime.exceptionThrown` as a row. */
export function rowFromException(
  id: number,
  details: ExceptionDetails,
  timestamp: number,
): ConsoleRow {
  const thrown = details.exception
  return {
    id,
    level: "error",
    type: "error",
    args: thrown === undefined ? [] : [thrown],
    // The exception's own text beats a rendered handle: Hermes puts the
    // message and the class in `text` and the object may have neither.
    text: thrown === undefined ? details.text : `${details.text} ${inlineSummary(thrown)}`.trim(),
    timestamp,
    source: details.url === undefined ? null : (details.url.split("/").pop() ?? null),
    local: false,
  }
}

/** A row this app wrote — a prompt echo, or a notice about the connection. */
export function localRow(id: number, level: Level, text: string, timestamp: number): ConsoleRow {
  return { id, level, type: "log", args: [], text, timestamp, source: null, local: true }
}

/**
 * Append, keeping the buffer bounded.
 *
 * Trimmed in one slice rather than a shift per row: a burst of a thousand lines
 * would otherwise be a thousand array copies.
 */
export function appended(
  rows: readonly ConsoleRow[],
  incoming: readonly ConsoleRow[],
  max = MAX_ROWS,
): ConsoleRow[] {
  const next = [...rows, ...incoming]
  return next.length <= max ? next : next.slice(next.length - max)
}

export interface FilterState {
  /** Which levels to show. Empty means all of them, not none. */
  levels: ReadonlySet<Level>
  query: string
}

/**
 * The rows a filter leaves.
 *
 * An empty level set means "everything", because a filter bar with nothing
 * ticked showing nothing is a console that looks broken.
 */
export function filtered(rows: readonly ConsoleRow[], filter: FilterState): ConsoleRow[] {
  const needle = filter.query.trim().toLowerCase()
  return rows.filter((row) => {
    if (filter.levels.size > 0 && !filter.levels.has(row.level)) return false
    if (needle === "") return true
    return row.text.toLowerCase().includes(needle)
  })
}

/** Toggling one level in the filter bar. */
export function toggleLevel(levels: ReadonlySet<Level>, level: Level): Set<Level> {
  const next = new Set(levels)
  if (next.has(level)) next.delete(level)
  else next.add(level)
  return next
}

/** How many of each level, for the filter bar's counters. */
export function levelCounts(rows: readonly ConsoleRow[]): Record<Level, number> {
  const counts: Record<Level, number> = { verbose: 0, info: 0, warning: 0, error: 0 }
  for (const row of rows) counts[row.level] += 1
  return counts
}

/** A row as a line of text, for copy. */
export function rowText(row: ConsoleRow): string {
  const stamp = new Date(row.timestamp).toISOString().slice(11, 23)
  const where = row.source === null ? "" : ` (${row.source})`
  return `${stamp} [${row.level}] ${row.text}${where}`
}
