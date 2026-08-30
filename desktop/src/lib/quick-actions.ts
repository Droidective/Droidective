import { isFoldedIntoHub } from "@/lib/hubs"
import { rankFeatures } from "@/lib/palette"
import type { CustomCommand } from "@/lib/wire"
import type { FeatureSummary } from "@/lib/wire"

/**
 * What the Quick Actions panel offers, and in what order.
 *
 * Ported from ADBKit's `PaletteSearch.quickActions`, which the Mac's panel and
 * nothing else uses. The rule that is easy to get wrong is the middle one: a
 * feature folded into a hub **is** offered here — the members are the quick
 * actions — and its enabledness rides on its hub, because the catalog only
 * manages a member through the hub it belongs to. Hiding them would empty the
 * panel of most of what it is for.
 */

/** The three kinds that can run without a screen. */
const ACTION_KINDS = new Set(["instantAction", "toggleAction", "formAction"])

export interface QuickActionsInput {
  query: string
  /** Features turned off in the catalog. */
  disabled: readonly string[]
  /** Pinned ids, in pin order. */
  favorites: readonly string[]
  /** Actions the user removed from the panel — `LayoutState.quickPanelHiddenIds`. */
  hidden: readonly string[]
}

/** Whether this feature can be reached from the panel at all. */
export function isPanelEligible(
  feature: FeatureSummary,
  disabled: readonly string[],
): boolean {
  if (!ACTION_KINDS.has(feature.kind) || !feature.implemented) return false
  // A member's enabledness is its hub's, since that is the only place the
  // catalog lets it be turned off.
  const owner = isFoldedIntoHub(feature) ? (feature.absorbedBy ?? feature.id) : feature.id
  return !disabled.includes(owner)
}

/**
 * The panel's action list.
 *
 * With no query, pinned actions lead in pin order and the rest follow in
 * registry order. With one, relevance decides and nothing is promoted — a
 * weakly-matching pin above an exact match would make the ranking a lie, which
 * is the same rule the in-app palette follows.
 */
export function quickActions(
  features: readonly FeatureSummary[],
  { query, disabled, favorites, hidden }: QuickActionsInput,
): FeatureSummary[] {
  const eligible = features.filter(
    (feature) => isPanelEligible(feature, disabled) && !hidden.includes(feature.id),
  )
  if (query.trim() !== "") return rankFeatures(eligible, query)
  const pinned = favorites.flatMap((id) => eligible.filter((feature) => feature.id === id))
  const rest = eligible.filter((feature) => !favorites.includes(feature.id))
  return [...pinned, ...rest]
}

/**
 * Every action the panel *could* show, for the Settings list that hides them.
 *
 * Registry order and no query: this is a list to tick through, not a search
 * result, and the panel's own pinning must not reorder it under someone.
 */
export function panelEligibleActions(
  features: readonly FeatureSummary[],
  disabled: readonly string[],
): FeatureSummary[] {
  return features.filter((feature) => isPanelEligible(feature, disabled))
}

/**
 * The full-app screens the panel lists under "Open in Droidective".
 *
 * Views and system screens, minus the hub members that are reached through
 * their hub — the same filter the sidebar applies, because this list is the
 * sidebar's contents seen from somewhere else.
 */
export function openableScreens(
  features: readonly FeatureSummary[],
  { query, disabled }: { query: string; disabled: readonly string[] },
): FeatureSummary[] {
  const screens = features.filter(
    (feature) =>
      !ACTION_KINDS.has(feature.kind) &&
      feature.implemented &&
      !isFoldedIntoHub(feature) &&
      !disabled.includes(feature.id),
  )
  return query.trim() === "" ? screens : rankFeatures(screens, query)
}

/** Saved commands matching the query — `PaletteSearch.commands`. */
export function quickCommands(
  commands: readonly CustomCommand[],
  query: string,
): CustomCommand[] {
  const needle = query.toLowerCase().trim()
  if (needle === "") return [...commands]
  return commands.filter(
    (command) =>
      command.name.toLowerCase().includes(needle) ||
      command.command.toLowerCase().includes(needle),
  )
}

/**
 * Moving the highlight around a grid with the arrow keys.
 *
 * Its own function because the edges are where a grid gets this wrong: left at
 * the first column steps to the previous row's last cell rather than stopping,
 * down from the last row lands on the last cell rather than nowhere, and
 * neither ever leaves the list. The Mac's panel behaves this way, and it is the
 * difference between arrows that feel like a grid and arrows that feel stuck.
 */
export function moveInGrid(
  count: number,
  current: number,
  direction: "up" | "down" | "left" | "right",
  columns: number,
): number {
  if (count <= 0) return 0
  const step = direction === "left" ? -1 : direction === "right" ? 1 : 0
  if (step !== 0) {
    return Math.min(count - 1, Math.max(0, current + step))
  }
  const row = direction === "up" ? current - columns : current + columns
  if (row < 0) return current % columns
  if (row >= count) return count - 1
  return row
}
