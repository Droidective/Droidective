import { useCallback, useEffect, useRef, useState } from "react"
import { HOME_TAB, loadLayout, restoreTabs, saveLayout, type LayoutState } from "@/lib/layout"
import { toggleCollapsed } from "@/lib/sidebar"
import {
  activateIndex,
  closeTab,
  openTab,
  reorderTabs,
  tabState,
  type TabState,
} from "@/lib/tabs"
import type { FeatureSummary } from "@/lib/wire"

export interface Workspace {
  tabs: TabState
  layout: LayoutState
  open: (id: string) => void
  close: (id: string) => void
  reorder: (id: string, before: string | null) => void
  activateIndex: (index: number) => void
  setSidebarOrder: (order: string[]) => void
  setCategoryOrder: (order: string[]) => void
  toggleCategory: (category: string) => void
}

/**
 * The window's arrangement: which tabs are open and how the sidebar is sorted,
 * restored on launch and saved as it changes.
 *
 * The decisions all live in `lib/` — this only sequences them, which is the
 * same split the Mac keeps between `AppState` and `TabState`/`SidebarOrdering`.
 */
export function useWorkspace(features: FeatureSummary[]): Workspace {
  const [layout, setLayout] = useState<LayoutState>(() => loadLayout(globalThis.localStorage))
  const [tabs, setTabs] = useState<TabState>(() => tabState([HOME_TAB], HOME_TAB))

  // Saved tabs name features, so they cannot be validated until the registry
  // has arrived. Once only: after this, the tab strip is the user's to change.
  const restored = useRef(false)
  useEffect(() => {
    if (restored.current || features.length === 0) return
    restored.current = true
    const known = new Set(features.map((feature) => feature.id))
    setTabs(restoreTabs(layout, (id) => known.has(id)))
  }, [features, layout])

  // Writing before the restore would save the placeholder strip over the real
  // one — the first launch of a session would forget every tab.
  useEffect(() => {
    if (!restored.current) return
    saveLayout(globalThis.localStorage, {
      ...layout,
      openTabs: [...tabs.openTabs],
      activeTab: tabs.activeTab,
    })
  }, [layout, tabs])

  const open = useCallback((id: string) => {
    setTabs((current) => openTab(current, id))
  }, [])

  const close = useCallback((id: string) => {
    // Home is permanent: it is where a closed last tab lands, so closing it
    // would be a move with nowhere to go.
    if (id === HOME_TAB) return
    setTabs((current) => closeTab(current, id, HOME_TAB))
  }, [])

  const reorder = useCallback((id: string, before: string | null) => {
    setTabs((current) => reorderTabs(current, id, before))
  }, [])

  const jump = useCallback((index: number) => {
    setTabs((current) => activateIndex(current, index))
  }, [])

  const setSidebarOrder = useCallback((sidebarOrder: string[]) => {
    setLayout((current) => ({ ...current, sidebarOrder }))
  }, [])

  const setCategoryOrder = useCallback((categoryOrder: string[]) => {
    setLayout((current) => ({ ...current, categoryOrder }))
  }, [])

  const toggleCategory = useCallback((category: string) => {
    setLayout((current) => ({
      ...current,
      collapsedCategories: toggleCollapsed(current.collapsedCategories, category),
    }))
  }, [])

  return {
    tabs,
    layout,
    open,
    close,
    reorder,
    activateIndex: jump,
    setSidebarOrder,
    setCategoryOrder,
    toggleCategory,
  }
}
