import { useCallback, useEffect, useState } from "react"
import { PaneArea } from "@/components/PaneArea"
import { noOverlays, ShellOverlays, type OverlayState } from "@/components/ShellOverlays"
import { Sidebar } from "@/components/Sidebar"
import { useShellKeys } from "@/hooks/useShellKeys"
import type { SidebarModeController } from "@/hooks/useSidebarMode"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import { isPeeked, occupiesLayout } from "@/lib/sidebarMode"
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
  workspace,
  sidebar,
}: {
  features: FeatureSummary[]
  device: Device | null
  /** Owned by `App`, because the device bar reads the focused feature from it. */
  workspace: WorkspaceController
  /** Owned by `App` too, because the device bar carries the sidebar button. */
  sidebar: SidebarModeController
}) {
  const [overlays, setOverlays] = useState<OverlayState>(noOverlays)
  const patch = useCallback((next: Partial<OverlayState>) => {
    setOverlays((current) => ({ ...current, ...next }))
  }, [])
  const [packageId, setPackageId] = useSelectedPackage(device?.serial ?? null)

  // Focus the pane first, so whatever is chosen opens in the one that asked.
  const { focusPane } = workspace
  const onNewTab = useCallback(
    (pane: number) => {
      focusPane(pane)
      patch({ palette: true })
    },
    [focusPane, patch],
  )

  const focused = activeTab(workspace.workspace)

  useShellKeys({
    activeTab: focused,
    workspace,
    sidebar,
    features,
    device,
    packageId,
    onPalette: () => {
      patch({ palette: true })
    },
    onSettings: () => {
      patch({ settings: true })
    },
  })

  const sidebarView = (
    <WorkspaceSidebar
      features={features}
      activeID={focused}
      workspace={workspace}
      onOpenSettings={() => {
        patch({ settings: true })
      }}
      onRowContextMenu={(id, x, y) => {
        patch({ rowMenu: { id, x, y }, recording: false })
      }}
    />
  )

  return (
    // `min-w-0` matters: a flex item defaults to `min-width: auto`, so without
    // it this refuses to shrink below its content and pushes the notification
    // panel off the right edge of the window rather than making room.
    // `relative` is what the auto-hiding sidebar is positioned against.
    <div className="relative flex min-h-0 min-w-0 flex-1">
      {occupiesLayout(sidebar.mode) ? sidebarView : null}
      {sidebar.mode.autoHide ? (
        <AutoHidingSidebar peeked={isPeeked(sidebar.mode)} onPeek={sidebar.peek}>
          {sidebarView}
        </AutoHidingSidebar>
      ) : null}

      <WorkspacePanes
        features={features}
        device={device}
        workspace={workspace}
        packageId={packageId}
        onSelectPackage={setPackageId}
        onNewTab={onNewTab}
        onContextMenu={(id, x, y) => {
          patch({ tabMenu: { id, x, y } })
        }}
      />

      <ShellOverlays
        features={features}
        workspace={workspace}
        state={overlays}
        onChange={patch}
      />
    </div>
  )
}

/**
 * Dock-style: a thin strip on the window's left edge that reveals the sidebar
 * over the content, which slides away again when the pointer leaves it.
 *
 * The strip stays present while the sidebar is out, so crossing from one to the
 * other does not read as leaving — a gap there makes the sidebar flicker shut
 * under a moving pointer.
 */
function AutoHidingSidebar({
  peeked,
  onPeek,
  children,
}: {
  peeked: boolean
  onPeek: (shown: boolean) => void
  children: React.ReactNode
}) {
  return (
    <div
      className="absolute inset-y-0 left-0 z-30 flex"
      onMouseEnter={() => {
        onPeek(true)
      }}
      onMouseLeave={() => {
        onPeek(false)
      }}
    >
      {/* The hover target when nothing is showing. Narrow enough to stay out
          of the way of the content underneath it. */}
      <div className="w-2 shrink-0" aria-hidden />
      {peeked ? <div className="flex shadow-2xl">{children}</div> : null}
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
  onOpenSettings,
  onRowContextMenu,
}: {
  features: FeatureSummary[]
  activeID: string | null
  workspace: WorkspaceController
  onOpenSettings: () => void
  onRowContextMenu: (id: string, x: number, y: number) => void
}) {
  return (
    <Sidebar
      disabledFeatures={workspace.layout.disabledFeatures}
      onOpenSettings={onOpenSettings}
      onContextMenu={onRowContextMenu}
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

/**
 * The pane area, wired to the workspace.
 *
 * Its own component for the reason `WorkspaceSidebar` is: every prop below is
 * a straight forward of `workspace.*`, and inline it buried what this file
 * actually decides.
 */
function WorkspacePanes({
  features,
  device,
  workspace,
  packageId,
  onSelectPackage,
  onNewTab,
  onContextMenu,
}: {
  features: FeatureSummary[]
  device: Device | null
  workspace: WorkspaceController
  packageId: string | null
  onSelectPackage: (packageId: string | null) => void
  onNewTab: (pane: number) => void
  onContextMenu: (id: string, x: number, y: number) => void
}) {
  const byID = (id: string) => features.find((feature) => feature.id === id) ?? null
  return (
    <PaneArea
      workspace={workspace.workspace}
      features={features}
      featureByID={byID}
      device={device}
      packageId={packageId}
      onSelectPackage={onSelectPackage}
      onOpen={workspace.open}
      onClose={workspace.close}
      onDrop={workspace.drop}
      onSplit={workspace.split}
      onFocusPane={workspace.focusPane}
      onContextMenu={onContextMenu}
      onNewTab={onNewTab}
      sidebarOrder={workspace.layout.sidebarOrder}
      categoryOrder={workspace.layout.categoryOrder}
      favorites={workspace.layout.favorites}
      disabledFeatures={workspace.layout.disabledFeatures}
      onSetEnabled={workspace.setFeatureEnabled}
      onSetGroupEnabled={workspace.setGroupEnabled}
      splitFraction={workspace.layout.splitFraction}
      onSplitFraction={workspace.setSplitFraction}
    />
  )
}

/**
 * The chosen app, and the rule that it does not survive a device change.
 *
 * Lifted out of the Apps pane because a `needsBundle` action needs the same
 * choice and so it cannot live inside one tab. Dropped on a new selection
 * because a package id means nothing on a different device — carrying it over
 * would silently target an app that may not be installed there.
 */
function useSelectedPackage(
  serial: string | null,
): [string | null, (packageId: string | null) => void] {
  const [packageId, setPackageId] = useState<string | null>(null)
  useEffect(() => {
    setPackageId(null)
  }, [serial])
  return [packageId, setPackageId]
}
