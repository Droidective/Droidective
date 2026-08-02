import type { FeatureSummary } from "@/lib/wire"
import { isRunnable } from "@/lib/wire"

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
 * The runnable features a query matches, best first.
 *
 * Registry order breaks ties — it is a curated order, and falling back to it
 * keeps the list stable as someone types rather than reshuffling equal-scoring
 * rows. Hub members are included: a hub is a whole screen this app does not
 * have yet, and hiding its members would make them unreachable rather than
 * merely relocated.
 */
export function searchActions(features: FeatureSummary[], query: string): FeatureSummary[] {
  const scored: { feature: FeatureSummary; score: number; order: number }[] = []
  features.forEach((feature, order) => {
    if (!isRunnable(feature)) return
    const score = relevance(feature, query)
    if (score > 0) scored.push({ feature, score, order })
  })
  scored.sort((a, b) => (a.score === b.score ? a.order - b.order : b.score - a.score))
  return scored.map((entry) => entry.feature)
}

/** Groups a ranked list by category, preserving rank order within each group. */
export function groupByCategory(
  features: FeatureSummary[],
): { category: string; features: FeatureSummary[] }[] {
  const groups: { category: string; features: FeatureSummary[] }[] = []
  for (const feature of features) {
    const existing = groups.find((group) => group.category === feature.category)
    if (existing) existing.features.push(feature)
    else groups.push({ category: feature.category, features: [feature] })
  }
  return groups
}

/** "deviceState" → "Device State". The wire sends case names, not labels. */
export function categoryLabel(category: string): string {
  const spaced = category.replaceAll(/([a-z\d])([A-Z])/gu, "$1 $2")
  return spaced.charAt(0).toUpperCase() + spaced.slice(1)
}
