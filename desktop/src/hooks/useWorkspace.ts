import { useCallback, useEffect, useRef, useState } from "react"
import {
  HOME_TAB,
  loadLayout,
  restoreWorkspaceFrom,
  saveLayout,
  type LayoutState,
} from "@/lib/layout"
import { withEnabled, withGroupEnabled } from "@/lib/catalog"
import { clampedFraction } from "@/lib/panes"
import { togglePinned } from "@/lib/palette"
import { toggleCollapsed } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"
import {
  activateAt,
  close,
  closeOthers,
  drop,
  focus,
  move,
  newWorkspace,
  open,
  split,
  type Workspace,
} from "@/lib/workspace"

export interface WorkspaceController {
  workspace: Workspace
  layout: LayoutState
  open: (id: string) => void
  close: (id: string) => void
  closeOthers: (id: string) => void
  drop: (id: string, pane: number, before: string | null) => void
  split: (id: string) => void
  moveToOtherPane: (id: string) => void
  focusPane: (pane: number) => void
  activateIndex: (index: number) => void
  setSplitFraction: (fraction: number) => void
  setSidebarOrder: (order: string[]) => void
  setCategoryOrder: (order: string[]) => void
  toggleCategory: (category: string) => void
  togglePin: (id: string) => void
  /** Turning one feature off in the catalog, or back on. */
  setFeatureEnabled: (id: string, enabled: boolean) => void
  /** A whole category at once — the Mac's right-click on a group header. */
  setGroupEnabled: (members: FeatureSummary[], enabled: boolean) => void
}

/**
 * The window's arrangement: which tabs are open in which pane, and how the
 * sidebar is sorted — restored on launch and saved as it changes.
 *
 * The decisions all live in `lib/` and this only sequences them, the same split
 * the Mac keeps between `AppState` and `Workspace`/`SidebarOrdering`.
 */
export function useWorkspace(features: FeatureSummary[]): WorkspaceController {
  const [layout, setLayout] = useState<LayoutState>(() => loadLayout(globalThis.localStorage))
  const [workspace, setWorkspace] = useState<Workspace>(() => newWorkspace(HOME_TAB))

  // Saved tabs name features, so they cannot be validated until the registry
  // has arrived. Once only: after this, the strip is the user's to change.
  const restored = useRef(false)
  useEffect(() => {
    if (restored.current || features.length === 0) return
    restored.current = true
    const known = new Set(features.map((feature) => feature.id))
    setWorkspace(restoreWorkspaceFrom(layout, (id) => known.has(id)))
  }, [features, layout])

  // Writing before the restore would save the placeholder over the real thing
  // — the first launch of a session would forget every tab.
  useEffect(() => {
    if (!restored.current) return
    saveLayout(globalThis.localStorage, {
      ...layout,
      panes: workspace.groups.map((group) => ({
        tabs: [...group.openTabs],
        activeTab: group.activeTab,
      })),
      focusedPane: workspace.focusedGroup,
    })
  }, [layout, workspace])

  const edit = useCallback(
    (transform: (current: Workspace) => Workspace) => {
      setWorkspace(transform)
    },
    [],
  )

  return {
    workspace,
    layout,
    open: useCallback((id: string) => {
      edit((current) => open(current, id))
    }, [edit]),
    // Home is permanent: it is where a closed last tab lands, so closing it
    // would be a move with nowhere to go.
    close: useCallback((id: string) => {
      if (id === HOME_TAB) return
      edit((current) => close(current, id, HOME_TAB))
    }, [edit]),
    closeOthers: useCallback((id: string) => {
      edit((current) => closeOthers(current, id, HOME_TAB))
    }, [edit]),
    drop: useCallback((id: string, pane: number, before: string | null) => {
      edit((current) => drop(current, id, pane, before))
    }, [edit]),
    split: useCallback((id: string) => {
      edit((current) => split(current, id))
    }, [edit]),
    moveToOtherPane: useCallback((id: string) => {
      edit((current) => move(current, id, current.focusedGroup === 0 ? 1 : 0))
    }, [edit]),
    focusPane: useCallback((pane: number) => {
      edit((current) => focus(current, pane))
    }, [edit]),
    activateIndex: useCallback((index: number) => {
      edit((current) => activateAt(current, index))
    }, [edit]),
    setSplitFraction: useCallback((splitFraction: number) => {
      setLayout((current) => ({ ...current, splitFraction: clampedFraction(splitFraction) }))
    }, []),
    setSidebarOrder: useCallback((sidebarOrder: string[]) => {
      setLayout((current) => ({ ...current, sidebarOrder }))
    }, []),
    setCategoryOrder: useCallback((categoryOrder: string[]) => {
      setLayout((current) => ({ ...current, categoryOrder }))
    }, []),
    togglePin: useCallback((id: string) => {
      setLayout((current) => ({ ...current, favorites: togglePinned(current.favorites, id) }))
    }, []),
    setFeatureEnabled: useCallback((id: string, enabled: boolean) => {
      setLayout((current) => ({
        ...current,
        disabledFeatures: withEnabled(current.disabledFeatures, id, enabled),
      }))
    }, []),
    setGroupEnabled: useCallback((members: FeatureSummary[], enabled: boolean) => {
      setLayout((current) => ({
        ...current,
        disabledFeatures: withGroupEnabled(current.disabledFeatures, members, enabled),
      }))
    }, []),
    toggleCategory: useCallback((category: string) => {
      setLayout((current) => ({
        ...current,
        collapsedCategories: toggleCollapsed(current.collapsedCategories, category),
      }))
    }, []),
  }
}
