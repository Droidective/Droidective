import { useCallback, useRef, useState } from "react"
import {
  neighborPane,
  removePane,
  singlePane,
  splitPane,
  type SplitDirection,
  type SplitNode,
} from "@/lib/terminal"

export interface TerminalTab {
  id: string
  /** 1-based, for the strip's label. Stable: closing tab 2 leaves 1 and 3. */
  ordinal: number
  /** What the user renamed it to, or null for the ordinal's "Shell N". */
  title: string | null
  tree: SplitNode
  /** Which pane in this tab has focus. */
  focused: string
}

/** What the strip shows: the given name, or the one derived from the ordinal. */
export function tabLabel(tab: TerminalTab): string {
  return tab.title ?? `Shell ${String(tab.ordinal)}`
}

export interface TerminalTabs {
  tabs: TerminalTab[]
  active: string | null
  /** Pane id → the device serial captured when that pane was created. */
  serials: Readonly<Record<string, string | null>>
  select: (tab: string) => void
  focus: (tab: string, pane: string) => void
  openTab: (serial: string | null) => void
  /** Splits the focused pane of the active tab. */
  split: (direction: SplitDirection, serial: string | null) => void
  /** Closes one pane, and the tab with it once its last pane goes. */
  closePane: (tab: string, pane: string) => void
  closeTab: (tab: string) => void
  /** +1 for the next tab, -1 for the previous. Wraps, as the Mac's does. */
  cycle: (by: 1 | -1) => void
  /** Renames a tab; an empty name puts the derived "Shell N" back. */
  rename: (tab: string, title: string) => void
}

/**
 * The terminal's tabs and the panes inside them.
 *
 * Deliberately *not* persisted. The Mac restores a terminal by reopening each
 * tab's last directory (`TerminalResume`), which needs the shell's cwd read out
 * of the kernel — `proc_pidinfo` there, `/proc/<pid>/cwd` on Linux, nothing on
 * Windows. Restoring tabs without their directories would look like the Mac and
 * behave differently, which is the one outcome the port is trying to avoid, so
 * this waits for the cwd half.
 */
export function useTerminalTabs(): TerminalTabs {
  const [tabs, setTabs] = useState<TerminalTab[]>([])
  const [active, setActive] = useState<string | null>(null)
  const [serials, setSerials] = useState<Record<string, string | null>>({})
  // A ref, not state: the label counter is read while deciding what to render
  // next, and a state read would be one render behind.
  const nextOrdinal = useRef(1)

  // The selection, resolved. `active` can name a tab that has since closed —
  // closing one does not go back and rewrite it — so everything below reads
  // this instead. Using the raw value would make `split` and `cycle` no-ops
  // right after a tab closed, which reads as the shortcut being broken.
  const selected = tabs.some((tab) => tab.id === active) ? active : (tabs[0]?.id ?? null)

  const openTab = useCallback((serial: string | null) => {
    const tab = crypto.randomUUID()
    const pane = crypto.randomUUID()
    const ordinal = nextOrdinal.current
    nextOrdinal.current += 1
    setSerials((current) => ({ ...current, [pane]: serial }))
    setTabs((current) => [
      ...current,
      { id: tab, ordinal, title: null, tree: singlePane(pane), focused: pane },
    ])
    setActive(tab)
  }, [])

  const split = useCallback(
    (direction: SplitDirection, serial: string | null) => {
      if (selected === null) return
      const pane = crypto.randomUUID()
      setSerials((current) => ({ ...current, [pane]: serial }))
      setTabs((current) =>
        current.map((tab) => {
          if (tab.id !== selected) return tab
          const tree = splitPane(tab.tree, tab.focused, direction, pane)
          return { ...tab, tree, focused: pane }
        }),
      )
    },
    [selected],
  )

  const closePane = useCallback((tab: string, pane: string) => {
    setTabs((current) => withoutPane(current, tab, pane))
    setSerials((current) => {
      const { [pane]: _closed, ...rest } = current
      return rest
    })
  }, [])

  const closeTab = useCallback((tab: string) => {
    setTabs((current) => current.filter((entry) => entry.id !== tab))
  }, [])

  const cycle = useCallback(
    (by: 1 | -1) => {
      const target = neighborTab(tabs, selected, by)
      if (target !== null) setActive(target)
    },
    [tabs, selected],
  )

  const rename = useCallback((tab: string, title: string) => {
    setTabs((current) => withTitle(current, tab, title))
  }, [])

  const focus = useCallback((tab: string, pane: string) => {
    setActive(tab)
    setTabs((current) =>
      current.map((entry) => (entry.id === tab ? { ...entry, focused: pane } : entry)),
    )
  }, [])

  return {
    tabs,
    // A closed active tab hands the selection on rather than leaving the pane
    // blank with tabs still in the strip.
    active: selected,
    serials,
    select: setActive,
    focus,
    openTab,
    split,
    closePane,
    closeTab,
    cycle,
    rename,
  }
}

// MARK: - the pure transitions
//
// Module-level so they are testable without a renderer, which is the only way
// this app tests anything: it has no DOM test environment.

/**
 * The tab `by` places from the selection, wrapping in both directions. Null
 * when there is nowhere to go.
 *
 * `+ tabs.length` before the modulo, because JavaScript's `%` keeps the sign —
 * going left off the front would otherwise land on index -1.
 */
export function neighborTab(
  tabs: readonly TerminalTab[],
  selected: string | null,
  by: 1 | -1,
): string | null {
  const index = tabs.findIndex((tab) => tab.id === selected)
  if (tabs.length < 2 || index < 0) return null
  return tabs[(index + by + tabs.length) % tabs.length]?.id ?? null
}

/** Renames a tab. An empty or blank name restores the derived "Shell N". */
export function withTitle(
  tabs: readonly TerminalTab[],
  tab: string,
  title: string,
): TerminalTab[] {
  const trimmed = title.trim()
  return tabs.map((entry) =>
    entry.id === tab ? { ...entry, title: trimmed.length > 0 ? trimmed : null } : entry,
  )
}

/**
 * Closes one pane. The tab goes with its last pane — the way ⌘W peels a pane
 * and then the tab on the Mac.
 */
export function withoutPane(
  tabs: readonly TerminalTab[],
  tab: string,
  pane: string,
): TerminalTab[] {
  const found = tabs.find((entry) => entry.id === tab)
  if (!found) return [...tabs]
  const next = removePane(found.tree, pane)
  if (next === null) return tabs.filter((entry) => entry.id !== tab)
  const focused =
    found.focused === pane ? (neighborPane(found.tree, pane) ?? found.focused) : found.focused
  return tabs.map((entry) => (entry.id === tab ? { ...entry, tree: next, focused } : entry))
}
