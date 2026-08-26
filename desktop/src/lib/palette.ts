import { withoutHubMembers } from "@/lib/hubs"
import type { FeatureSummary } from "@/lib/wire"

/**
 * The palette's ordering, ported from ADBKit's `FeatureDef.relevance` and
 * `PaletteSearch`.
 *
 * Ported rather than reinvented so the two apps rank the same query the same
 * way — the score bands below are the Swift ones, including the deliberate
 * quirk that an all-words title match (50) sits *below* a contiguous title
 * substring (60).
 */

/** Zero means "no match", and a feature scoring zero is not shown at all. */
export function relevance(feature: FeatureSummary, query: string): number {
  const q = query.toLowerCase().trim()
  if (q === "") return 1

  const title = feature.title.toLowerCase()
  if (title === q) return 100
  if (title.startsWith(q)) return 80
  if (title.includes(q)) return 60

  const keywords = feature.keywords.map((keyword) => keyword.toLowerCase())
  if (keywords.some((keyword) => keyword.startsWith(q))) return 40
  if (keywords.some((keyword) => keyword.includes(q))) return 30

  const subtitle = feature.subtitle?.toLowerCase() ?? ""
  if (subtitle !== "" && subtitle.includes(q)) return 10

  // Multi-word: every word has to appear somewhere searchable, contiguous or
  // not, so "copy ip" finds "Copy Device IP".
  const tokens = q.split(" ").filter((token) => token !== "")
  if (tokens.length <= 1) return 0
  if (tokens.every((token) => title.includes(token))) return 50
  const haystacks = [...keywords, title, subtitle]
  if (tokens.every((token) => haystacks.some((hay) => hay.includes(token)))) return 20
  return 0
}

/**
 * The features a query matches, best first — the ones that score nothing are
 * dropped.
 *
 * The incoming order breaks ties. Callers hand this the registry order (or
 * their own arrangement of it), which is curated, and falling back to it keeps
 * the list stable as someone types rather than reshuffling equal-scoring rows.
 *
 * *Which* features to offer is the caller's decision, not this function's: the
 * sidebar lists everything the engine implements, and a palette over commands
 * would choose differently again.
 */
export function rankFeatures(
  features: readonly FeatureSummary[],
  query: string,
): FeatureSummary[] {
  const scored: { feature: FeatureSummary; score: number; order: number }[] = []
  features.forEach((feature, order) => {
    const score = relevance(feature, query)
    if (score > 0) scored.push({ feature, score, order })
  })
  return scored
    .toSorted((a, b) => (a.score === b.score ? a.order - b.order : b.score - a.score))
    .map((entry) => entry.feature)
}

/**
 * What the palette lists.
 *
 * With no query, pinned features lead, in the order they were pinned — the
 * palette opens on what you actually use. With one, relevance decides and
 * nothing is promoted: a weakly-matching pin sitting above an exact match
 * would make the ranking a lie.
 */
export function paletteResults(
  features: readonly FeatureSummary[],
  query: string,
  favorites: readonly string[],
): FeatureSummary[] {
  // A member of a hub this app has built is reached through the hub, so it is
  // not offered separately — the hub carries its keywords, which is what keeps
  // searching "decompile" working. A member whose hub is not built here stays.
  const listable = withoutHubMembers(features)
  if (query.trim() !== "") return rankFeatures(listable, query)
  const pinned = favorites.flatMap((id) => listable.filter((feature) => feature.id === id))
  const rest = listable.filter((feature) => !favorites.includes(feature.id))
  return [...pinned, ...rest]
}

/** Move a highlighted row by `delta`, wrapping at both ends. */
export function moveHighlight(count: number, current: number, delta: number): number {
  if (count <= 0) return 0
  return (current + delta + count) % count
}

/** Add or remove `id` from the pinned list. */
export function togglePinned(favorites: readonly string[], id: string): string[] {
  return favorites.includes(id)
    ? favorites.filter((entry) => entry !== id)
    : [...favorites, id]
}
