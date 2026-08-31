import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { usePreferenceEditors } from "@/hooks/useLayoutPreferences"
import {
  currentWindowLabel,
  HOME_TAB,
  loadLayout,
  loadWindowLayout,
  restoreWorkspaceFrom,
  saveLayout,
  saveWindowLayout,
  type LayoutState,
} from "@/lib/layout"
import { withEnabled, withGroupEnabled } from "@/lib/catalog"
import { withHotkey, type Hotkey } from "@/lib/hotkeys"
import { clampedFraction } from "@/lib/panes"
import { togglePinned } from "@/lib/palette"
import { toggleCollapsed } from "@/lib/sidebar"
import type { FeatureSummary } from "@/lib/wire"
import {
  activateAt,
  close,
  closeOthers,
  cycleBackward,
  cycleForward,
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
  /** +1 for the next tab in the focused pane, -1 for the previous. */
  cycleTab: (by: 1 | -1) => void
  setSplitFraction: (fraction: number) => void
  setSidebarOrder: (order: string[]) => void
  setCategoryOrder: (order: string[]) => void
  toggleCategory: (category: string) => void
  togglePin: (id: string) => void
  /** Turning one feature off in the catalog, or back on. */
  setFeatureEnabled: (id: string, enabled: boolean) => void
  /** A whole category at once — the Mac's right-click on a group header. */
  setGroupEnabled: (members: FeatureSummary[], enabled: boolean) => void
  /** Binds a feature's shortcut, or clears it with null. */
  setHotkey: (id: string, hotkey: Hotkey | null) => void
  /** The device bar's Run on all switch. */
  setRunOnAll: (on: boolean) => void
  /** Pinned sidebar or Dock-style auto-hide. */
  setSidebarAutoHide: (autoHide: boolean) => void
  /** Whether closing the window hides the app behind the tray. */
  setKeepRunningInBackground: (on: boolean) => void
  /** Adds or removes one feature from the tray's chosen list. */
  setTrayItem: (id: string, listed: boolean) => void
  /** Shows or hides one action in the Quick Actions panel. */
  setQuickPanelAction: (id: string, shown: boolean) => void
  setQuickPanelCloseAfterRun: (on: boolean) => void
  /** The panel's global shortcut, or null to clear it. */
  setQuickPanelHotkey: (hotkey: Hotkey | null) => void
  /** +1 zooms in, -1 out, 0 back to Actual Size. */
  zoom: (direction: -1 | 0 | 1) => void
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
  // Tabs and panes belong to *this* window. Two windows share one
  // `localStorage`, so they are kept under separate keys rather than merged
  // into one document — see `window-layout.ts`.
  const windowLabel = useMemo(() => currentWindowLabel(globalThis.location.search), [])

  // Saved tabs name features, so they cannot be validated until the registry
  // has arrived. Once only: after this, the strip is the user's to change.
  const restored = useRef(false)
  useEffect(() => {
    if (restored.current || features.length === 0) return
    restored.current = true
    const known = new Set(features.map((feature) => feature.id))
    const own = loadWindowLayout(globalThis.localStorage, windowLabel, layout)
    setWorkspace(
      restoreWorkspaceFrom(
        { ...layout, panes: own.panes, focusedPane: own.focusedPane },
        (id) => known.has(id),
      ),
    )
  }, [features, layout, windowLabel])

  // Writing before the restore would save the placeholder over the real thing
  // — the first launch of a session would forget every tab.
  useEffect(() => {
    if (!restored.current) return
    // The shared half keeps the app-wide settings; the panes go to this
    // window's own key. Writing them to the shared blob is what would let one
    // window clobber the other's tabs.
    saveLayout(globalThis.localStorage, layout)
    const own = loadWindowLayout(globalThis.localStorage, windowLabel, layout)
    saveWindowLayout(globalThis.localStorage, windowLabel, {
      ...own,
      panes: workspace.groups.map((group) => ({
        tabs: [...group.openTabs],
        activeTab: group.activeTab,
      })),
      focusedPane: workspace.focusedGroup,
    })
  }, [layout, workspace, windowLabel])

  const edit = useCallback(
    (transform: (current: Workspace) => Workspace) => {
      setWorkspace(transform)
    },
    [],
  )

  return {
    workspace,
    layout,
    ...useLayoutEditors(setLayout),
    ...usePreferenceEditors(setLayout),
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
    cycleTab: useCallback((by: 1 | -1) => {
      edit((current) => (by === 1 ? cycleForward(current) : cycleBackward(current)))
    }, [edit]),
  }
}

/**
 * Everything that edits the persisted layout rather than the open tabs.
 *
 * Split from the workspace above because they are two different things sharing
 * one hook: the tab operations transform a `Workspace`, and these all patch one
 * field of `LayoutState`.
 */
function useLayoutEditors(
  setLayout: React.Dispatch<React.SetStateAction<LayoutState>>,
): Pick<
  WorkspaceController,
  | "setSplitFraction"
  | "setSidebarOrder"
  | "setCategoryOrder"
  | "togglePin"
  | "setFeatureEnabled"
  | "setGroupEnabled"
  | "setHotkey"
  | "toggleCategory"
> {
  return {
    setSplitFraction: useCallback(
      (splitFraction: number) => {
        setLayout((current) => ({ ...current, splitFraction: clampedFraction(splitFraction) }))
      },
      [setLayout],
    ),
    setSidebarOrder: useCallback(
      (sidebarOrder: string[]) => {
        setLayout((current) => ({ ...current, sidebarOrder }))
      },
      [setLayout],
    ),
    setCategoryOrder: useCallback(
      (categoryOrder: string[]) => {
        setLayout((current) => ({ ...current, categoryOrder }))
      },
      [setLayout],
    ),
    togglePin: useCallback(
      (id: string) => {
        setLayout((current) => ({ ...current, favorites: togglePinned(current.favorites, id) }))
      },
      [setLayout],
    ),
    setFeatureEnabled: useCallback(
      (id: string, enabled: boolean) => {
        setLayout((current) => ({
          ...current,
          disabledFeatures: withEnabled(current.disabledFeatures, id, enabled),
        }))
      },
      [setLayout],
    ),
    setGroupEnabled: useCallback(
      (members: FeatureSummary[], enabled: boolean) => {
        setLayout((current) => ({
          ...current,
          disabledFeatures: withGroupEnabled(current.disabledFeatures, members, enabled),
        }))
      },
      [setLayout],
    ),
    setHotkey: useCallback(
      (id: string, hotkey: Hotkey | null) => {
        setLayout((current) => ({ ...current, hotkeys: withHotkey(current.hotkeys, id, hotkey) }))
      },
      [setLayout],
    ),
    toggleCategory: useCallback(
      (category: string) => {
        setLayout((current) => ({
          ...current,
          collapsedCategories: toggleCollapsed(current.collapsedCategories, category),
        }))
      },
      [setLayout],
    ),
  }
}

