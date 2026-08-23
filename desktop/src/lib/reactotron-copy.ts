/**
 * What each copy verb hands to the clipboard.
 *
 * Pure and gathered in one place, because the difference between them is the
 * whole point and it is easy to blur: **line** is the row as read (badge,
 * status, headline), **object** is the frame's payload as the app sent it,
 * **value** is one node of the tree, and **events** is a run of rows as JSON.
 * The Mac offers the same four, and someone moving between the two apps should
 * get the same text from the same verb.
 */

import { prettyJson, type JsonValue } from "@/lib/json"
import { presentation, rowText, type TimelineRow } from "@/lib/reactotron-rows"
import type { TreeRow } from "@/lib/json-tree"

/** The collapsed row, as one line of text. */
export function copyLine(row: TimelineRow): string {
  return rowText(presentation(row.event))
}

/**
 * The frame's payload, indented. Null when the frame carried none — `clear` and
 * the relay's own notices do not, and a verb that silently copies "null" is
 * worse than one that is not offered.
 */
export function copyObject(row: TimelineRow): string | null {
  const payload = row.command.payload
  return payload === undefined ? null : prettyJson(payload)
}

/**
 * One tree node.
 *
 * What the row *shows*: the parsed object while a stringified payload stands as
 * one, and the raw string the app sent once it has been switched back. Copying
 * the escaped text from under a rendered object is the kind of surprise that
 * makes someone stop trusting the button.
 */
export function copyValue(row: TreeRow): string {
  return typeof row.value === "string" ? row.value : prettyJson(row.value)
}

/**
 * A run of rows as JSON: the **raw wire commands**, indented.
 *
 * One shape for the file, the clipboard and a selection, as on the Mac. Raw
 * rather than enriched on purpose — a badge and a headline are this app's
 * rendering choices, and putting them in a machine-readable export invites a
 * script to depend on something that is free to change. What the app sent is
 * not.
 */
export function copyEventsAsJson(rows: readonly TimelineRow[]): string {
  return prettyJson(rows.map((row) => wireShape(row)))
}

/**
 * One row as the wire saw it.
 *
 * Upstream's own field names, unchanged — a script reading an export should not
 * have to learn a second spelling of a contract that is not ours. The optional
 * fields are omitted rather than sent as null, so the export reads like the
 * frame that produced it.
 */
function wireShape(row: TimelineRow): JsonValue {
  const record: Record<string, JsonValue> = { type: row.command.type }
  if (row.command.payload !== undefined) record["payload"] = row.command.payload
  if (row.command.important !== undefined) record["important"] = row.command.important
  if (row.command.date !== undefined) record["date"] = row.command.date
  if (row.command.deltaTime !== undefined) record["deltaTime"] = row.command.deltaTime
  return record
}
