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

/**
 * Move `tab` so it sits immediately before `target`.
 *
 * **The destination follows the target**, which is the rule worth stating:
 * dropping before a loose tab makes the moved one loose, and dropping before a
 * grouped tab puts it in that group. A separate "which group am I dropping
 * into?" decision at the call site would be a second answer to a question the
 * target already settles, and the two would disagree the first time a group
 * was dragged past another.
 *
 * A no-op when either id is unknown, or they are the same.
 */
export function moveTabBefore(entries: readonly Entry[], tab: string, target: string): Entry[] {
  if (tab === target || !hasTab(entries, tab) || !hasTab(entries, target)) return [...entries]
  const without = removeTab(entries, tab)
  // The target can be gone from `without` only when it shared the moved tab's
  // group and that group emptied — impossible, since it still holds the target.
  return insertBefore(without, tab, target)
}

/** Move `tab` to the end of `groupId`. A no-op if it is already the only one there. */
export function moveTabToGroup(entries: readonly Entry[], tab: string, groupId: string): Entry[] {
  const group = entries.find(
    (entry) => entry.kind === "group" && entry.group.id === groupId,
  )
  if (!hasTab(entries, tab) || group?.kind !== "group") return [...entries]
  if (group.group.tabIds.length === 1 && group.group.tabIds[0] === tab) return [...entries]
  return addTab(removeTab(entries, tab), tab, groupId)
}

/** Move `tab` out of whatever holds it, to the end of the strip. */
export function moveTabToEnd(entries: readonly Entry[], tab: string): Entry[] {
  if (!hasTab(entries, tab)) return [...entries]
  const last = entries.at(-1)
  if (last?.kind === "tab" && last.id === tab) return [...entries]
  return [...removeTab(entries, tab), { kind: "tab", id: tab }]
}

/**
 * Move a whole group before another top-level entry.
 *
 * `target` is an entry id — a group's, or a loose tab's — because the strip's
 * top level holds both and a group can be dragged past either.
 */
export function moveGroupBefore(entries: readonly Entry[], id: string, target: string): Entry[] {
  if (id === target) return [...entries]
  const from = entries.findIndex((entry) => entry.kind === "group" && entry.group.id === id)
  if (from === -1) return [...entries]
  const moving = entries[from]
  if (moving === undefined) return [...entries]
  const rest = entries.filter((_, index) => index !== from)
  const to = rest.findIndex((entry) => entryId(entry) === target)
  // A target that is not a top-level entry leaves the group where it was,
  // rather than silently sending it to one end.
  if (to === -1) return [...entries]
  return [...rest.slice(0, to), moving, ...rest.slice(to)]
}

/** Move a whole group to the end of the strip. */
export function moveGroupToEnd(entries: readonly Entry[], id: string): Entry[] {
  const from = entries.findIndex((entry) => entry.kind === "group" && entry.group.id === id)
  if (from === -1) return [...entries]
  const moving = entries[from]
  if (moving === undefined) return [...entries]
  return [...entries.filter((_, index) => index !== from), moving]
}

/** A top-level entry's own id: a group's, or the loose tab's. */
export function entryId(entry: Entry): string {
  return entry.kind === "tab" ? entry.id : entry.group.id
}

function hasTab(entries: readonly Entry[], id: string): boolean {
  return allTabIds(entries).includes(id)
}

/** Put `tab` immediately before `target`, wherever the target sits. */
function insertBefore(entries: readonly Entry[], tab: string, target: string): Entry[] {
  const out: Entry[] = []
  for (const entry of entries) {
    if (entry.kind === "tab") {
      if (entry.id === target) out.push({ kind: "tab", id: tab })
      out.push(entry)
      continue
    }
    const at = entry.group.tabIds.indexOf(target)
    if (at === -1) {
      out.push(entry)
      continue
    }
    const tabIds = [...entry.group.tabIds]
    tabIds.splice(at, 0, tab)
    out.push({ kind: "group", group: { ...entry.group, tabIds } })
  }
  return out
}
