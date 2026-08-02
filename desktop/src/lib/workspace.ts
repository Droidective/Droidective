import { moveBefore, moveToEnd } from "@/lib/ordering"
import {
  activateIndex,
  activateNext,
  activatePrevious,
  closeOtherTabs,
  closeTab,
  openTab,
  tabState,
  type TabState,
} from "@/lib/tabs"

/**
 * One or two panes side by side, plus which one holds focus — ported from
 * ADBKit's `Workspace`.
 *
 * The fiddly rules are all here rather than in a component, for the reason the
 * Swift version gives: collapsing an emptied pane, keeping ids globally unique,
 * keeping a pane focused, and never leaving the workspace empty are exactly the
 * things that go wrong and exactly the things worth testing without a window.
 *
 * A feature id is open in at most one pane, so moving a tab across is a move
 * and not a copy.
 */
export interface Workspace {
  /** The open panes, left to right — always 1 or 2. */
  readonly groups: readonly TabState[]
  /** Which pane new tabs, close and cycle act on. Always a valid index. */
  readonly focusedGroup: number
}

/** A fresh workspace with a single pane showing `fallback`. */
export function newWorkspace(fallback: string): Workspace {
  return { groups: [tabState([fallback], fallback)], focusedGroup: 0 }
}

/**
 * Rebuild from persisted panes, enforcing every invariant: at most two panes,
 * ids valid and globally unique, a non-empty result, and an in-range focus.
 */
export function restoreWorkspace(
  persisted: readonly { tabs: readonly string[]; activeTab: string | null }[],
  focusedGroup: number,
  fallback: string,
  isKnownTab: (id: string) => boolean,
): Workspace {
  const seen = new Set<string>()
  const groups: TabState[] = []
  for (const group of persisted.slice(0, 2)) {
    const valid = group.tabs.filter((id) => {
      if (!isKnownTab(id) || seen.has(id)) return false
      seen.add(id)
      return true
    })
    if (valid.length > 0) groups.push(tabState(valid, group.activeTab))
  }
  if (groups.length === 0) return newWorkspace(fallback)
  return { groups, focusedGroup: Math.min(Math.max(focusedGroup, 0), groups.length - 1) }
}

// MARK: reads

/** The focused pane's active tab — what the sidebar highlights. */
export function activeTab(workspace: Workspace): string | null {
  return workspace.groups[workspace.focusedGroup]?.activeTab ?? null
}

/** Every pane's active tab. Both fronts are on screen, so both are "active". */
export function activeTabs(workspace: Workspace): string[] {
  return workspace.groups.flatMap((group) => (group.activeTab === null ? [] : [group.activeTab]))
}

export function isSplit(workspace: Workspace): boolean {
  return workspace.groups.length > 1
}

export function groupIndexOf(workspace: Workspace, id: string): number {
  return workspace.groups.findIndex((group) => group.openTabs.includes(id))
}

/** Every open tab, in pane order — what the keep-alive body renders. */
export function allOpenTabs(workspace: Workspace): string[] {
  return workspace.groups.flatMap((group) => [...group.openTabs])
}

// MARK: mutations

/** Open `id`, or refocus it wherever it already is. New tabs land in focus. */
export function open(workspace: Workspace, id: string): Workspace {
  const existing = groupIndexOf(workspace, id)
  const at = existing === -1 ? workspace.focusedGroup : existing
  return { groups: replace(workspace.groups, at, (group) => openTab(group, id)), focusedGroup: at }
}

/**
 * Close `id` wherever it is. Collapses an emptied second pane; reseeds
 * `fallback` when the last pane would empty; keeps focus in range.
 */
export function close(workspace: Workspace, id: string, fallback: string): Workspace {
  const at = groupIndexOf(workspace, id)
  if (at === -1) return workspace
  const closed = closeTab(workspace.groups[at] ?? tabState([]), id)
  if (closed.openTabs.length > 0) {
    return {
      groups: replace(workspace.groups, at, () => closed),
      focusedGroup: workspace.focusedGroup,
    }
  }
  if (workspace.groups.length > 1) {
    const groups = workspace.groups.filter((_, index) => index !== at)
    return { groups, focusedGroup: Math.min(workspace.focusedGroup, groups.length - 1) }
  }
  // The last pane never goes empty.
  return { groups: [tabState([fallback], fallback)], focusedGroup: 0 }
}

/** Close every tab in `id`'s pane except it and the permanent `keep`. */
export function closeOthers(workspace: Workspace, id: string, keep: string): Workspace {
  const at = groupIndexOf(workspace, id)
  if (at === -1) return workspace
  return {
    groups: replace(workspace.groups, at, (group) => closeOtherTabs(group, id, keep)),
    focusedGroup: at,
  }
}

/**
 * Move `id` into pane `dest`, appending and activating it. Collapses the source
 * pane if it empties. A no-op for the same pane or an index that is not there.
 */
export function move(workspace: Workspace, id: string, dest: number): Workspace {
  const src = groupIndexOf(workspace, id)
  if (src === -1 || src === dest || !(dest >= 0 && dest < workspace.groups.length)) return workspace
  const groups = workspace.groups.map((group, index) => {
    if (index === src) return closeTab(group, id)
    if (index === dest) return openTab(group, id)
    return group
  })
  const collapsed = groups.filter((group, index) => index !== src || group.openTabs.length > 0)
  const landed = collapsed.findIndex((group) => group.openTabs.includes(id))
  return { groups: collapsed, focusedGroup: landed === -1 ? 0 : landed }
}

/**
 * Split: move `id` into a new second pane. Needs its pane to hold more than one
 * tab — something has to stay behind — and no existing split.
 */
export function split(workspace: Workspace, id: string): Workspace {
  const src = groupIndexOf(workspace, id)
  if (workspace.groups.length !== 1 || src === -1) return workspace
  if ((workspace.groups[src]?.openTabs.length ?? 0) < 2) return workspace
  return {
    groups: [closeTab(workspace.groups[src] ?? tabState([]), id), tabState([id], id)],
    focusedGroup: 1,
  }
}

/** Reorder `id` within its own pane so it sits before `target` (null = end). */
export function reorder(workspace: Workspace, id: string, target: string | null): Workspace {
  const at = groupIndexOf(workspace, id)
  if (at === -1) return workspace
  return {
    groups: replace(workspace.groups, at, (group) => {
      const openTabs =
        target === null ? moveToEnd(id, group.openTabs) : moveBefore(id, target, group.openTabs)
      return { openTabs, activeTab: group.activeTab }
    }),
    focusedGroup: workspace.focusedGroup,
  }
}

/** Resolve a strip drop: reorder inside a pane, or move across and position. */
export function drop(
  workspace: Workspace,
  id: string,
  dest: number,
  target: string | null,
): Workspace {
  const src = groupIndexOf(workspace, id)
  if (src === -1) return workspace
  if (src === dest) return target === null ? workspace : reorder(workspace, id, target)
  const moved = move(workspace, id, dest)
  return target === null ? moved : reorder(moved, id, target)
}

export function cycleForward(workspace: Workspace): Workspace {
  return mapFocused(workspace, activateNext)
}

export function cycleBackward(workspace: Workspace): Workspace {
  return mapFocused(workspace, activatePrevious)
}

/** Activate the tab at a 0-based index in the focused pane. */
export function activateAt(workspace: Workspace, index: number): Workspace {
  return mapFocused(workspace, (group) => activateIndex(group, index))
}

/** Give a pane focus — clicking one of its tabs, or anywhere in its body. */
export function focus(workspace: Workspace, index: number): Workspace {
  if (index === workspace.focusedGroup) return workspace
  if (!(index >= 0 && index < workspace.groups.length)) return workspace
  return { groups: workspace.groups, focusedGroup: index }
}

function mapFocused(workspace: Workspace, transform: (group: TabState) => TabState): Workspace {
  return {
    groups: replace(workspace.groups, workspace.focusedGroup, transform),
    focusedGroup: workspace.focusedGroup,
  }
}

function replace(
  groups: readonly TabState[],
  at: number,
  transform: (group: TabState) => TabState,
): TabState[] {
  return groups.map((group, index) => (index === at ? transform(group) : group))
}

