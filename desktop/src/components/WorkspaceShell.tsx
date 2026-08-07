import { useCallback, useEffect, useState } from "react"
import { CommandPalette } from "@/components/CommandPalette"
import { PaneArea } from "@/components/PaneArea"
import { Sidebar } from "@/components/Sidebar"
import { TabContextMenu } from "@/components/TabContextMenu"
import type { TabMenuTarget } from "@/components/TabMenu"
import { useTabShortcuts } from "@/hooks/useTabShortcuts"
import { useWorkspace } from "@/hooks/useWorkspace"
import type { Device, FeatureSummary } from "@/lib/wire"
import { activeTab } from "@/lib/workspace"

/**
 * The window below the device bar: the sidebar, the panes, and the tab menu.
 *
 * Split from `App` so that file stays about getting the daemon up and this one
 * is about arranging what the daemon serves.
 */
export function WorkspaceShell({
  features,
  device,
}: {
  features: FeatureSummary[]
  device: Device | null
}) {
  const workspace = useWorkspace(features)
  const [menu, setMenu] = useState<TabMenuTarget | null>(null)
  const [paletteOpen, setPaletteOpen] = useState(false)
  // Lifted out of the Apps pane: a `needsBundle` action needs the same choice,
  // so it cannot live inside one tab. A package id means nothing on a different
  // device, so the choice is dropped when the selection changes.
  const [packageId, setPackageId] = useState<string | null>(null)
  const serial = device?.serial ?? null
  useEffect(() => {
    setPackageId(null)
  }, [serial])

  const byID = useCallback(
    (id: string) => features.find((feature) => feature.id === id) ?? null,
    [features],
  )

  // Focus the pane first, so whatever is chosen opens in the one that asked.
  const { focusPane } = workspace
  const onNewTab = useCallback(
    (pane: number) => {
      focusPane(pane)
      setPaletteOpen(true)
    },
    [focusPane],
  )

  const focused = activeTab(workspace.workspace)
  useTabShortcuts({
    activeTab: focused,
    onClose: workspace.close,
    onActivateIndex: workspace.activateIndex,
    onSplit: workspace.split,
    onPalette: () => {
      setPaletteOpen(true)
    },
  })

  return (
    // `min-w-0` matters: a flex item defaults to `min-width: auto`, so without
    // it this refuses to shrink below its content and pushes the notification
    // panel off the right edge of the window rather than making room.
    <div className="flex min-h-0 min-w-0 flex-1">
      <WorkspaceSidebar features={features} activeID={focused} workspace={workspace} />

      <PaneArea
        workspace={workspace.workspace}
        features={features}
        featureByID={byID}
        device={device}
        packageId={packageId}
        onSelectPackage={setPackageId}
        onOpen={workspace.open}
        onClose={workspace.close}
        onDrop={workspace.drop}
        onSplit={workspace.split}
        onFocusPane={workspace.focusPane}
        onContextMenu={(id, x, y) => {
          setMenu({ id, x, y })
        }}
        onNewTab={onNewTab}
        sidebarOrder={workspace.layout.sidebarOrder}
        categoryOrder={workspace.layout.categoryOrder}
        favorites={workspace.layout.favorites}
        splitFraction={workspace.layout.splitFraction}
        onSplitFraction={workspace.setSplitFraction}
      />

      <Overlays
        palette={paletteOpen}
        menu={menu}
        features={features}
        workspace={workspace}
        onDismissPalette={() => {
          setPaletteOpen(false)
        }}
        onDismissMenu={() => {
          setMenu(null)
        }}
      />
    </div>
  )
}

/**
 * The sidebar, wired to the workspace.
 *
 * Its own component only because every one of these props is a straight
 * forward of `workspace.layout.*` — thirteen lines of plumbing that say
 * nothing about what the shell does.
 */
function WorkspaceSidebar({
  features,
  activeID,
  workspace,
}: {
  features: FeatureSummary[]
  activeID: string | null
  workspace: ReturnType<typeof useWorkspace>
}) {
  return (
    <Sidebar
      features={features}
      activeID={activeID}
      onOpen={workspace.open}
      sidebarOrder={workspace.layout.sidebarOrder}
      categoryOrder={workspace.layout.categoryOrder}
      collapsedCategories={workspace.layout.collapsedCategories}
      favorites={workspace.layout.favorites}
      onTogglePinned={workspace.togglePin}
      onSidebarOrder={workspace.setSidebarOrder}
      onCategoryOrder={workspace.setCategoryOrder}
      onToggleCollapsed={workspace.toggleCategory}
    />
  )
}

/** The two things that float over the panes. */
function Overlays({
  palette,
  menu,
  features,
  workspace,
  onDismissPalette,
  onDismissMenu,
}: {
  palette: boolean
  menu: TabMenuTarget | null
  features: FeatureSummary[]
  workspace: ReturnType<typeof useWorkspace>
  onDismissPalette: () => void
  onDismissMenu: () => void
}) {
  return (
    <>
      {palette ? (
        <CommandPalette
          features={features}
          favorites={workspace.layout.favorites}
          onOpen={workspace.open}
          onTogglePinned={workspace.togglePin}
          onDismiss={onDismissPalette}
        />
      ) : null}
      {menu === null ? null : (
        <TabContextMenu target={menu} workspace={workspace} onDismiss={onDismissMenu} />
      )}
    </>
  )
}
