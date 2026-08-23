/**
 * A JSON *string* that is itself JSON: an API request whose `data` field
 * carries a stringified body, a log whose message is a serialized object.
 * Reactotron shows what the app sent — a wall of escaped text — where the
 * reader wants the object.
 *
 * A port of ADBKit's `EmbeddedJSON`. The two halves stay deliberately separate:
 * `looksLikeJson` is what a row asks on every render to decide whether to offer
 * the parse, so it only touches the string's first and last non-whitespace
 * characters. `parseEmbedded` is the walk of the whole payload, and is only ever
 * called for the one value a reader opened — a streaming timeline must never
 * parse what nobody looked at.
 */

import { isJsonObject, type JsonValue } from "@/lib/json"

/**
 * Longest string (in UTF-8 bytes) worth parsing. Past this the parse is itself
 * the stall, so the value keeps its raw text and offers nothing.
 */
export const maxEmbeddedBytes = 1_000_000

/**
 * The string's size in bytes, not characters.
 *
 * `TextEncoder` allocates a copy of the whole string, which defeats the point
 * of a cheap guard, so the bound is checked against the *character* count
 * first: UTF-8 is at most 3 bytes per UTF-16 unit, so anything under a third of
 * the budget is certainly inside it and anything over it is certainly outside.
 * Only the narrow band between them is measured.
 */
export function withinByteBudget(text: string, maxBytes: number): boolean {
  if (text.length <= maxBytes / 3) return true
  if (text.length > maxBytes) return false
  return new TextEncoder().encode(text).length <= maxBytes
}

function isSpace(character: string): boolean {
  return character.trim() === ""
}

/**
 * True when `text` is *shaped* like a JSON object or array — the cheap check,
 * whitespace-tolerant, made per row render.
 *
 * Scanning in from both ends rather than trimming either: `trimStart()` on a
 * megabyte body copies the megabyte to look at one character, which is the cost
 * this function exists to avoid.
 */
export function looksLikeJson(text: string): boolean {
  if (!withinByteBudget(text, maxEmbeddedBytes)) return false
  let start = 0
  while (start < text.length && isSpace(text.charAt(start))) start++
  const opener = text.charAt(start)
  const closer = opener === "{" ? "}" : opener === "[" ? "]" : ""
  if (closer === "") return false
  let end = text.length - 1
  while (end > start && isSpace(text.charAt(end))) end--
  return text.charAt(end) === closer
}

/**
 * The parsed object or array, or null when the string is not one (or is bigger
 * than `maxEmbeddedBytes`). Call this when the value is opened, never while
 * building a row.
 */
export function parseEmbedded(text: string): JsonValue | null {
  if (!looksLikeJson(text)) return null
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    return null
  }
  const parsed = value as JsonValue
  return Array.isArray(parsed) || isJsonObject(parsed) ? parsed : null
}
