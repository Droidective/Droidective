/**
 * The JS Console's export, in ADBKit's `ConsoleExport` shape.
 *
 * One deterministic JSON shape shared by "save as a file" and "copy to the
 * clipboard", and the same one the Mac writes — a console dump should read the
 * same whichever app produced it, which is the whole point of matching rather
 * than inventing a second format here.
 */

import { captureStamp } from "@/lib/capture-stamp"
import type { ConsoleRow } from "@/lib/console-feed"

/** `log` · `input` · `result` · `error` · `notice`, as the Mac names them. */
export type ExportType = "log" | "input" | "result" | "error" | "notice"

/** The prompt echo's leading marker (U+203A), written by `localRow`. */
const ECHO = "›"

/**
 * Which kind of entry a row is.
 *
 * The Mac carries this on `JSEntry.kind`; here it is derived, because the feed
 * models a row as level + text and adding a parallel field would be a second
 * thing to keep true. Every branch is pinned by a test, since the derivation is
 * the part that can silently drift as the row constructors change.
 */
export function exportType(row: ConsoleRow): ExportType {
  if (!row.local) return row.type === "error" ? "error" : "log"
  if (row.text.startsWith(ECHO)) return "input"
  // A result carries the evaluated value; a notice this app wrote carries none.
  return row.args.length > 0 ? "result" : "notice"
}

interface Line {
  timestamp: string
  type: ExportType
  level?: string
  text: string
}

/**
 * ISO 8601 with fractional seconds.
 *
 * Console bursts land several entries inside one second, so whole-second
 * stamps would read as ties — the Mac's formatter makes the same choice.
 */
function stamp(milliseconds: number): string {
  return new Date(milliseconds).toISOString()
}

/**
 * The rows as the export's JSON.
 *
 * Pretty-printed with the keys in sorted order, matching `ConsoleExport.json`,
 * so the two apps' files diff against each other cleanly. `level` is omitted
 * for the entries that have none rather than written as null, which is what
 * `Encodable` does with a nil `String?`.
 */
export function consoleJson(rows: readonly ConsoleRow[]): string {
  const lines = rows.map((row): Line => {
    const type = exportType(row)
    const line: Line = { text: row.text, timestamp: stamp(row.timestamp), type }
    if (type === "log") line.level = row.level
    return line
  })
  // Keys in the order `JSONEncoder.sortedKeys` produces them: level, text,
  // timestamp, type. `JSON.stringify` follows insertion order, so they are
  // written in that order rather than sorted afterwards.
  return JSON.stringify(
    lines.map((line) => ({
      ...(line.level === undefined ? {} : { level: line.level }),
      text: line.text,
      timestamp: line.timestamp,
      type: line.type,
    })),
    null,
    2,
  )
}

/** The file name an export suggests — `js-console_<stamp>.json`, as the Mac's. */
export function exportFileName(now: Date): string {
  return `js-console_${captureStamp(now)}.json`
}
