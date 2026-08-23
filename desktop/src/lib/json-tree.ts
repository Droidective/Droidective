/**
 * The object tree's row model: a JSON value flattened into the rows a reader
 * sees, in the order they are drawn.
 *
 * Pure, so the two things that are easy to get subtly wrong are testable
 * without a renderer. First, **order**: object children sort by key and array
 * items keep their index, because `json-search.ts` hands back ordinal paths in
 * exactly that order and a click on a result has to land on the right row.
 * Second, **grafting**: a value that is itself a string of JSON shows as the
 * object it holds, with the parse's rows taking the string's place — so a path
 * runs straight through it and the reader never sees the escaped wall.
 *
 * ADBKit's twin is the row half of `JSONTreeView`. Its *geometry* half
 * (`JSONTreeLayout`) deliberately does not come across: it computes how many
 * characters fit a wrapped line because SwiftUI's `lineLimit` is a drawing
 * instruction the reported height does not follow. A DOM wraps text natively
 * and line-clamps correctly, so porting that arithmetic would port the
 * workaround rather than the behaviour.
 */

import { parseEmbedded } from "@/lib/embedded-json"
import { compactJson, isJsonObject, type JsonValue } from "@/lib/json"

export interface TreeRow {
  /** Ordinal path from the root, matching `json-search.ts`'s `TreeMatch.path`. */
  path: number[]
  /** The same route as a string, for React keys and expansion state. */
  key: string
  /** `name` for an object child, `[3]` for an array item, "" for the root. */
  label: string
  depth: number
  value: JsonValue
  /** True when this row has children, whether or not they are shown. */
  isContainer: boolean
  /** How many children it has, for the collapsed summary. */
  count: number
  /** True when its children are being shown. Always true for the root. */
  isExpanded: boolean
  /**
   * True when the row's value arrived as a *string* of JSON and is being shown
   * as the object inside it. The row offers a way back to the raw text: some
   * payloads are only readable raw — an encoded token, a signed blob.
   */
  isParsed: boolean
}

/** How the reader has opened the tree: expanded paths, and paths forced raw. */
export interface TreeState {
  expanded: ReadonlySet<string>
  /**
   * Paths the reader switched back to the raw string. Parsed is the default
   * because it is the readable form; this is the escape hatch, not the norm.
   */
  raw: ReadonlySet<string>
}

export function emptyTreeState(): TreeState {
  return { expanded: new Set(), raw: new Set() }
}

export function pathKey(path: readonly number[]): string {
  return path.join(".")
}

export function toggled(set: ReadonlySet<string>, key: string): Set<string> {
  const next = new Set(set)
  if (next.has(key)) next.delete(key)
  else next.add(key)
  return next
}

/**
 * Every path along `path`, so opening a search result opens its ancestors too.
 * A result three levels down is useless if the reader has to find the way in.
 */
export function pathsTo(path: readonly number[]): string[] {
  return path.map((_, index) => pathKey(path.slice(0, index + 1)))
}

/** Most rows built in one pass. A state tree can be enormous; a reader is not. */
export const MAX_TREE_ROWS = 4000

/**
 * The visible rows, depth-first, parents before children.
 *
 * Only expanded containers contribute children, so a collapsed state tree costs
 * one row however big it is — which is what makes this safe to call per render.
 */
export function treeRows(
  root: JsonValue,
  state: TreeState,
  limit: number = MAX_TREE_ROWS,
): TreeRow[] {
  const rows: TreeRow[] = []

  const walk = (raw: JsonValue, label: string, path: number[], depth: number) => {
    if (rows.length >= limit) return
    const key = pathKey(path)
    // The value the reader sees. A string of JSON shows as its object unless
    // this row was switched back to the raw text.
    const parsed = state.raw.has(key) ? null : embedded(raw)
    const value = parsed ?? raw
    const container = childrenOf(value)
    // The root is always open — a tree whose single row is "{ 12 }" is a
    // disclosure triangle where a payload should be.
    const isExpanded = container !== null && (path.length === 0 || state.expanded.has(key))
    rows.push({
      path,
      key,
      label,
      depth,
      value,
      isContainer: container !== null,
      count: container?.length ?? 0,
      isExpanded,
      isParsed: parsed !== null,
    })
    if (container === null || !isExpanded) return
    for (const [index, child] of container.entries()) {
      walk(child.value, child.label, [...path, index], depth + 1)
    }
  }

  walk(root, "", [], 0)
  return rows
}

/** A container's children in render order, or null when it has none. */
function childrenOf(value: JsonValue): { label: string; value: JsonValue }[] | null {
  if (Array.isArray(value)) {
    return value.map((item, index) => ({ label: `[${index}]`, value: item }))
  }
  if (!isJsonObject(value)) return null
  // Sorted by key — the order `json-search.ts` counts in.
  return Object.keys(value)
    .toSorted()
    .map((key) => ({ label: key, value: value[key] ?? null }))
}

/**
 * The object a stringified payload holds, or null when it is not one.
 *
 * Called per visible row, which is why the cheap shape check in
 * `looksLikeJson` runs first and the parse only ever touches a row the reader
 * has on screen — never the whole payload.
 */
function embedded(value: JsonValue): JsonValue | null {
  return typeof value === "string" ? parseEmbedded(value) : null
}

/**
 * A row's value on one line: containers summarize, strings quote, everything
 * else prints as itself. The same shape `json-search.ts` previews a match with,
 * so a result and the row it scrolls to read the same.
 */
export function rowPreview(row: TreeRow, maxLength = 400): string {
  if (Array.isArray(row.value)) return `[ ${row.value.length} ]`
  if (isJsonObject(row.value)) return `{ ${Object.keys(row.value).length} }`
  if (typeof row.value === "string") return `"${clip(row.value, maxLength)}"`
  return String(row.value)
}

/** A leaf's full text, for the row that has been opened to show all of it. */
export function rowText(row: TreeRow): string {
  return typeof row.value === "string" ? row.value : compactJson(row.value)
}

function clip(text: string, maxLength: number): string {
  return text.length <= maxLength ? text : `${text.slice(0, maxLength)}…`
}
