/**
 * Find-in-console (⌘F on the Mac, Ctrl+F here).
 *
 * **Not the filter.** The filter hides rows; find leaves every row where it is
 * and walks between the ones that match, highlighting them. "Show me only
 * this" and "where is this?" are different questions, and the Mac keeps them as
 * two controls for that reason — the filter sits in the bar, find is its own
 * strip that opens on the shortcut.
 */

import type { ConsoleRow } from "@/lib/console-feed"

/** The query, normalized the way `ConsoleQuery` normalizes it. */
export function normalized(query: string): string {
  return query.trim().toLowerCase()
}

/**
 * The ids of the rows a query matches, in the order the feed shows them.
 *
 * Over the rows *already filtered*, because find searches what is on screen:
 * walking to a match hidden behind the level picker would scroll to a row that
 * is not there.
 */
export function findMatches(rows: readonly ConsoleRow[], query: string): number[] {
  const needle = normalized(query)
  if (needle === "") return []
  return rows.filter((row) => row.text.toLowerCase().includes(needle)).map((row) => row.id)
}

/** The match the arrows are currently on, or null when there are none. */
export function currentMatch(matches: readonly number[], index: number): number | null {
  if (matches.length === 0) return null
  return matches[Math.min(index, matches.length - 1)] ?? null
}

/**
 * What the counter reads.
 *
 * Blank while nothing has been typed — an empty field with "No matches" beside
 * it reads as a broken search rather than an unused one.
 */
export function countLabel(query: string, matches: readonly number[], index: number): string {
  if (normalized(query) === "") return ""
  if (matches.length === 0) return "No matches"
  return `${String(Math.min(index, matches.length - 1) + 1)} of ${String(matches.length)}`
}

/**
 * The next match, wrapping.
 *
 * Clamped before it steps, because the feed is live: matches can be trimmed out
 * from under an index while someone is reading, and stepping from a stale
 * index would skip rows or land past the end.
 */
export function nextIndex(index: number, count: number): number {
  if (count === 0) return 0
  return (Math.min(index, count - 1) + 1) % count
}

/** The previous match, wrapping. */
export function prevIndex(index: number, count: number): number {
  if (count === 0) return 0
  return (Math.min(index, count - 1) - 1 + count) % count
}

/** One run of text, marked when it is part of a match. */
export interface Segment {
  text: string
  match: boolean
}

/**
 * `text` split into matched and unmatched runs, for the highlight.
 *
 * Case-insensitive, and it returns the *original* casing — highlighting by
 * rebuilding from the lowercased copy would quietly rewrite every line it
 * touched.
 */
export function segments(text: string, query: string): Segment[] {
  const needle = normalized(query)
  if (needle === "") return [{ text, match: false }]
  const haystack = text.toLowerCase()
  const out: Segment[] = []
  let at = 0
  for (;;) {
    const found = haystack.indexOf(needle, at)
    if (found === -1) break
    if (found > at) out.push({ text: text.slice(at, found), match: false })
    out.push({ text: text.slice(found, found + needle.length), match: true })
    at = found + needle.length
  }
  if (at < text.length) out.push({ text: text.slice(at), match: false })
  return out
}
