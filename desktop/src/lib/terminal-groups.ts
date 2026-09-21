/**
 * The terminal rail's top-level rows: loose tabs, and groups of tabs.
 *
 * A port of ADBKit's `TerminalTabs`, entry for entry, because the parts that go
 * subtly wrong are invariants rather than drawing. Three of them:
 *
 * - **a group left empty deletes itself**, so closing the last tab in one never
 *   leaves a header with nothing under it;
 * - **grouping a tab that is already grouped detaches it first**, and the new
 *   group lands at the end — a tab cannot be in two places;
 * - **removing a group hands back the tab ids it held**, in order, because the
 *   caller owns the shells and has to tear them down. Dropping them here would
 *   leave pty sessions running with nothing on screen.
 */

export interface TabGroup {
  id: string
  name: string
  collapsed: boolean
  tabIds: string[]
}

export type Entry = { kind: "tab"; id: string } | { kind: "group"; group: TabGroup }

/** What a group is called when it is made without a name. */
export const DEFAULT_GROUP_NAME = "Group"

export function emptyEntries(): Entry[] {
  return []
}

/** Every tab id in display order — loose tabs and each group's, top to bottom. */
export function allTabIds(entries: readonly Entry[]): string[] {
  return entries.flatMap((entry) => (entry.kind === "tab" ? [entry.id] : entry.group.tabIds))
}

/** The group holding `id`, or null when the tab is loose. */
export function groupOfTab(entries: readonly Entry[], id: string): TabGroup | null {
  for (const entry of entries) {
    if (entry.kind === "group" && entry.group.tabIds.includes(id)) return entry.group
  }
  return null
}

/** Append a tab — loose, or into `groupId` when given. */
export function addTab(entries: readonly Entry[], id: string, groupId?: string): Entry[] {
  if (groupId === undefined) return [...entries, { kind: "tab", id }]
  let placed = false
  const next = entries.map((entry): Entry => {
    if (entry.kind !== "group" || entry.group.id !== groupId) return entry
    placed = true
    return { kind: "group", group: { ...entry.group, tabIds: [...entry.group.tabIds, id] } }
  })
  // A group that has gone means the tab still belongs somewhere: loose, rather
  // than dropped on the floor.
  return placed ? next : [...entries, { kind: "tab", id }]
}

/**
 * Wrap `tab` in a new group.
 *
 * A loose tab becomes a group **in place**, so the rail does not reorder under
 * the cursor. A tab that is already grouped detaches first and the new group
 * lands at the end — it cannot be in two.
 */
export function newGroup(
  entries: readonly Entry[],
  tab: string,
  name: string,
  id: string,
): Entry[] {
  const groupName = name.trim() === "" ? DEFAULT_GROUP_NAME : name.trim()
  const loose = entries.findIndex((entry) => entry.kind === "tab" && entry.id === tab)
  if (loose !== -1) {
    const next = [...entries]
    next[loose] = { kind: "group", group: { id, name: groupName, collapsed: false, tabIds: [tab] } }
    return next
  }
  if (groupOfTab(entries, tab) === null) return [...entries]
  return [
    ...removeTab(entries, tab),
    { kind: "group", group: { id, name: groupName, collapsed: false, tabIds: [tab] } },
  ]
}

/** Renames a group. An empty or whitespace name is ignored, not applied. */
export function renameGroup(entries: readonly Entry[], id: string, name: string): Entry[] {
  if (name.trim() === "") return [...entries]
  return entries.map((entry) =>
    entry.kind === "group" && entry.group.id === id
      ? { kind: "group", group: { ...entry.group, name: name.trim() } }
      : entry,
  )
}

export function setCollapsed(entries: readonly Entry[], id: string, collapsed: boolean): Entry[] {
  return entries.map((entry) =>
    entry.kind === "group" && entry.group.id === id
      ? { kind: "group", group: { ...entry.group, collapsed } }
      : entry,
  )
}

/**
 * Remove a group, handing back the tab ids it held in order.
 *
 * The caller owns the shells: dropping the ids here would leave pty sessions
 * running with nothing on screen to close them from.
 */
export function removeGroup(
  entries: readonly Entry[],
  id: string,
): { entries: Entry[]; closed: string[] } {
  const found = entries.find((entry) => entry.kind === "group" && entry.group.id === id)
  const closed = found?.kind === "group" ? found.group.tabIds : []
  return {
    entries: entries.filter((entry) => !(entry.kind === "group" && entry.group.id === id)),
    closed,
  }
}

/** Remove a tab from wherever it sits. A group left empty deletes itself. */
export function removeTab(entries: readonly Entry[], id: string): Entry[] {
  const out: Entry[] = []
  for (const entry of entries) {
    if (entry.kind === "tab") {
      if (entry.id !== id) out.push(entry)
      continue
    }
    const tabIds = entry.group.tabIds.filter((one) => one !== id)
    if (tabIds.length > 0) out.push({ kind: "group", group: { ...entry.group, tabIds } })
  }
  return out
}
