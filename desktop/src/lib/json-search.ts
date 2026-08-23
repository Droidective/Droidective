/**
 * Find inside a JSON tree — Reactotron payloads, the store browser.
 *
 * A port of ADBKit's `JSONSearch`. Matches carry *ordinal* paths that follow the
 * tree view's render order — object children sorted by key, array items in
 * order — so clicking a result can expand straight to its row. That coupling is
 * the whole reason the sort lives here rather than in the view: two orders drift
 * and the click lands on the wrong row.
 */

import { looksLikeJson, parseEmbedded, withinByteBudget } from "@/lib/embedded-json"
import { isJsonObject, type JsonValue } from "@/lib/json"

/**
 * Longest stringified payload expanded during a search. A find runs per
 * keystroke, so the parse it may trigger is capped well below the display
 * parse's `maxEmbeddedBytes`; a bigger string is searched as text.
 */
export const maxStringifiedBytes = 262_144

export interface TreeMatch {
  /** Child indices from the root, in render order. */
  path: number[]
  /** The same route spelled for a human: `data.items[3].id`. */
  displayPath: string
  preview: string
  isContainer: boolean
}

export interface SearchOptions {
  limit?: number
  maxVisited?: number
  /**
   * Search a string that is itself JSON as the object it holds, matching what
   * the tree view renders — the escaped text is not what the reader sees, and
   * `data.params.storeId` is the row they want, not the 4 KB blob that contains
   * it. Ordinal paths stay aligned with the view, which grafts a parse's rows in
   * the string's place. Strings past `maxStringifiedBytes` are left as text.
   */
  expandingStringifiedJson?: boolean
}

/**
 * One-line value preview matching the tree rows: containers summarize, strings
 * quote, everything else prints as itself.
 */
export function valuePreview(value: JsonValue): string {
  if (Array.isArray(value)) return `[ ${value.length} ]`
  if (isJsonObject(value)) return `{ ${Object.keys(value).length} }`
  if (typeof value === "string") return `"${value}"`
  return String(value)
}

/**
 * Every node whose own key or scalar value contains `query`
 * (case-insensitive), in render order. Bounded by `limit` results and
 * `maxVisited` visited nodes so a pathological payload cannot stall a
 * keystroke.
 */
export function jsonMatches(
  root: JsonValue,
  query: string,
  options: SearchOptions = {},
): TreeMatch[] {
  const needle = query.toLowerCase()
  if (needle === "") return []
  const limit = options.limit ?? 200
  const maxVisited = options.maxVisited ?? 40_000
  const expanding = options.expandingStringifiedJson ?? false
  const out: TreeMatch[] = []
  let visited = 0

  function matchesSelf(value: JsonValue, key: string): boolean {
    if (key.toLowerCase().includes(needle)) return true
    if (typeof value === "string") return value.toLowerCase().includes(needle)
    // A container matches through its children, never on its own summary. Null
    // matches on neither: it prints as "null" but a search for the word wants
    // the app's own text, and a store full of empty fields would bury it.
    if (value === null || Array.isArray(value) || isJsonObject(value)) return false
    return String(value).includes(needle)
  }

  /**
   * The object a stringified payload holds, when the caller asked for that and
   * it is small enough to parse mid-keystroke.
   */
  function expansion(value: JsonValue): JsonValue | null {
    if (!expanding || typeof value !== "string") return null
    if (!looksLikeJson(value)) return null
    if (!withinByteBudget(value, maxStringifiedBytes)) return null
    return parseEmbedded(value)
  }

  function walk(raw: JsonValue, key: string, path: number[], displayPath: string): void {
    if (out.length >= limit || visited >= maxVisited) return
    visited++
    // Search the value the reader sees: for a stringified payload that is its
    // object, so the escaped text neither matches on its own nor hides the
    // leaves inside it.
    const value = expansion(raw) ?? raw
    if (path.length > 0 && matchesSelf(value, key)) {
      out.push({
        path,
        displayPath,
        preview: valuePreview(value),
        isContainer: Array.isArray(value) || isJsonObject(value),
      })
    }
    if (Array.isArray(value)) {
      for (const [index, item] of value.entries()) {
        walk(item, `[${index}]`, [...path, index], `${displayPath}[${index}]`)
      }
      return
    }
    if (!isJsonObject(value)) return
    // Sorted by key — the same order the tree view renders, so the ordinal
    // path lands on the right row.
    for (const [index, entryKey] of Object.keys(value).toSorted().entries()) {
      const child = displayPath === "" ? entryKey : `${displayPath}.${entryKey}`
      walk(value[entryKey] ?? null, entryKey, [...path, index], child)
    }
  }

  walk(root, "", [], "")
  return out
}
