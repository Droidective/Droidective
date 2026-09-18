/**
 * The saved Send Text snippets, as the screen and the Quick Actions panel
 * show them.
 *
 * The *rules* for what a snippet may be — the trimmed, length-clamped name,
 * the uniqueness check, the use-count bump — are `Presets`' own methods in
 * ADBKit and reach this app as daemon verbs, so neither side can invent a
 * different idea of a valid snippet. What is here is the ordering and the
 * filtering, which are display decisions the panel needs synchronously while
 * somebody is typing; both are ported from `Presets.recentSnippets` and
 * `SendTextSnippet.matches` and tested against their rules.
 */

export interface Snippet {
  name: string
  text: string
  uses: number
  /** Epoch seconds of the last insert; null for a snippet never used. */
  lastUsedAt: number | null
}

/** Names longer than this are clamped, so chips and rows stay short. */
export const NAME_LIMIT = 24

/** How many the Quick Actions panel shows before "Show N more". */
export const PANEL_VISIBLE = 5

/**
 * Most recently used first.
 *
 * `Presets.recentSnippets`' comparator exactly: freshness wins, a snippet that
 * has never been used sorts after every one that has, and ties fall back to
 * the use count and then to the order they were saved in. That last tie-break
 * is why this takes the array's own order as meaningful — a stable sort alone
 * would leave it to the engine.
 */
export function recent(snippets: readonly Snippet[], limit?: number): Snippet[] {
  const ranked = snippets
    .map((snippet, index) => ({ snippet, index }))
    .toSorted((left, right) => {
      const a = left.snippet.lastUsedAt
      const b = right.snippet.lastUsedAt
      if (a !== null && b !== null && a !== b) return b - a
      if (a !== null && b === null) return -1
      if (a === null && b !== null) return 1
      if (left.snippet.uses !== right.snippet.uses) return right.snippet.uses - left.snippet.uses
      return left.index - right.index
    })
    .map((entry) => entry.snippet)
  return limit === undefined ? ranked : ranked.slice(0, limit)
}

/**
 * Case-insensitive match on the name or the inserted text.
 *
 * Both halves, as `SendTextSnippet.matches` does: somebody looking for the
 * snippet holding their test email searches for the email, not the label they
 * gave it a month ago.
 */
export function matches(snippet: Snippet, query: string): boolean {
  const trimmed = query.trim()
  if (trimmed === "") return true
  const needle = trimmed.toLowerCase()
  return (
    snippet.name.toLowerCase().includes(needle) || snippet.text.toLowerCase().includes(needle)
  )
}

export function filtered(snippets: readonly Snippet[], query: string): Snippet[] {
  return snippets.filter((snippet) => matches(snippet, query))
}

/** The placeholders the UI offers as chips, in `SnippetPlaceholders.known`'s order. */
export const PLACEHOLDERS: readonly string[] = ["clipboard", "ip"]

/**
 * Whether a name may be saved, and why not.
 *
 * The daemon refuses the same three cases with a 409 — this is what greys the
 * Save button out before anyone presses it, not a second authority.
 */
export function nameProblem(name: string, existing: readonly Snippet[]): string | null {
  const trimmed = name.trim()
  if (trimmed === "") return "A snippet needs a name."
  if (existing.some((snippet) => snippet.name === trimmed.slice(0, NAME_LIMIT))) {
    return "That name is already taken."
  }
  return null
}

/** What the Quick Actions panel shows, and what it keeps behind "Show N more". */
export function panelSplit(
  snippets: readonly Snippet[],
  expanded: boolean,
): { shown: Snippet[]; hidden: number } {
  const ranked = recent(snippets)
  if (expanded) return { shown: ranked, hidden: 0 }
  return {
    shown: ranked.slice(0, PANEL_VISIBLE),
    hidden: Math.max(0, ranked.length - PANEL_VISIBLE),
  }
}

/**
 * Where the keyboard lands after ↓ or ↑.
 *
 * Clamped rather than wrapped: the panel's list sits under a text field, and
 * pressing ↑ at the top should return focus to typing rather than jumping to
 * the last snippet. -1 means "no snippet highlighted".
 */
export function moveHighlight(current: number, delta: number, count: number): number {
  if (count === 0) return -1
  return Math.min(count - 1, Math.max(-1, current + delta))
}
