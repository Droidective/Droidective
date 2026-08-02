import { useCallback, useEffect, useState } from "react"
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

  const focused = activeTab(workspace.workspace)
  useTabShortcuts({
    activeTab: focused,
    onClose: workspace.close,
    onActivateIndex: workspace.activateIndex,
    onSplit: workspace.split,
  })

  return (
    <div className="flex min-h-0 flex-1">
      <Sidebar
        features={features}
        activeID={focused}
        onOpen={workspace.open}
        sidebarOrder={workspace.layout.sidebarOrder}
        categoryOrder={workspace.layout.categoryOrder}
        collapsedCategories={workspace.layout.collapsedCategories}
        onSidebarOrder={workspace.setSidebarOrder}
        onCategoryOrder={workspace.setCategoryOrder}
        onToggleCollapsed={workspace.toggleCategory}
      />

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
        sidebarOrder={workspace.layout.sidebarOrder}
        categoryOrder={workspace.layout.categoryOrder}
        splitFraction={workspace.layout.splitFraction}
        onSplitFraction={workspace.setSplitFraction}
      />

      {menu === null ? null : (
        <TabContextMenu
          target={menu}
          workspace={workspace}
          onDismiss={() => {
            setMenu(null)
          }}
        />
      )}
    </div>
  )
}
