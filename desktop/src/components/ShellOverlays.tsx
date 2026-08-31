import { CommandPalette } from "@/components/CommandPalette"
import { FeatureRowMenu, type FeatureMenuTarget } from "@/components/FeatureRowMenu"
import { FileDropLayer } from "@/components/FileDropLayer"
import { SettingsWindow } from "@/components/SettingsWindow"
import { TabContextMenu, type TabMenuTarget } from "@/components/TabContextMenu"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import type { FeatureSummary } from "@/lib/wire"

/** Everything floating over the panes, and whether it is up. */
export interface OverlayState {
  palette: boolean
  tabMenu: TabMenuTarget | null
  rowMenu: FeatureMenuTarget | null
  /** The row menu has turned into its hotkey recorder. */
  recording: boolean
  settings: boolean
}

export function noOverlays(): OverlayState {
  return { palette: false, tabMenu: null, rowMenu: null, recording: false, settings: false }
}

/**
 * The palette, the two context menus, and the Settings window.
 *
 * Together in one component because they are one idea — what is up over the
 * panes — and because the shell that owns the panes should not also carry a
 * closure per overlay. `onChange` takes a patch, so a caller opening one thing
 * says only what changed.
 */
export function ShellOverlays({
  features,
  workspace,
  state,
  onChange,
  activeFeature,
}: {
  features: FeatureSummary[]
  workspace: WorkspaceController
  state: OverlayState
  onChange: (next: Partial<OverlayState>) => void
  /** The focused tab, which decides where a dropped file would go. */
  activeFeature: string | null
}) {
  return (
    <>
      <FileDropLayer activeFeature={activeFeature} />
      {state.palette ? (
        <CommandPalette
          features={features}
          favorites={workspace.layout.favorites}
          onOpen={workspace.open}
          onTogglePinned={workspace.togglePin}
          onDismiss={() => {
            onChange({ palette: false })
          }}
        />
      ) : null}

      {state.tabMenu === null ? null : (
        <TabContextMenu
          target={state.tabMenu}
          workspace={workspace}
          onDismiss={() => {
            onChange({ tabMenu: null })
          }}
        />
      )}

      <RowMenu
        target={state.rowMenu}
        features={features}
        workspace={workspace}
        recording={state.recording}
        onChange={onChange}
      />

      {state.settings ? (
        <SettingsWindow
          general={{
            features,
            keepRunningInBackground: workspace.layout.keepRunningInBackground,
            onKeepRunningInBackground: workspace.setKeepRunningInBackground,
            trayItems: workspace.layout.trayItems,
            onTrayItem: workspace.setTrayItem,
            quickPanelHiddenIds: workspace.layout.quickPanelHiddenIds,
            onQuickPanelAction: workspace.setQuickPanelAction,
            quickPanelCloseAfterRun: workspace.layout.quickPanelCloseAfterRun,
            onQuickPanelCloseAfterRun: workspace.setQuickPanelCloseAfterRun,
            sidebarOrder: workspace.layout.sidebarOrder,
            categoryOrder: workspace.layout.categoryOrder,
            favorites: workspace.layout.favorites,
            disabledFeatures: workspace.layout.disabledFeatures,
          }}
          appearance={{
            sidebarAutoHide: workspace.layout.sidebarAutoHide,
            onSidebarAutoHide: workspace.setSidebarAutoHide,
            zoomStep: workspace.layout.zoomStep,
            onZoom: workspace.zoom,
          }}
          hotkeys={{
            features,
            bindings: workspace.layout.hotkeys,
            onChange: workspace.setHotkey,
            panelHotkey: workspace.layout.quickPanelHotkey,
            onPanelHotkey: workspace.setQuickPanelHotkey,
            sidebarOrder: workspace.layout.sidebarOrder,
            categoryOrder: workspace.layout.categoryOrder,
            favorites: workspace.layout.favorites,
            disabledFeatures: workspace.layout.disabledFeatures,
          }}
          onDismiss={() => {
            onChange({ settings: false })
          }}
        />
      ) : null}
    </>
  )
}

/**
 * A sidebar row's menu, wired to the workspace.
 *
 * Its own component so the list above stays a list, rather than six closures
 * that each look the same feature up again.
 */
function RowMenu({
  target,
  features,
  workspace,
  recording,
  onChange,
}: {
  target: FeatureMenuTarget | null
  features: FeatureSummary[]
  workspace: WorkspaceController
  recording: boolean
  onChange: (next: Partial<OverlayState>) => void
}) {
  if (target === null) return null
  // A row whose feature has since gone away: render nothing rather than a menu
  // whose items act on nothing.
  const feature = features.find((candidate) => candidate.id === target.id)
  if (feature === undefined) return null

  const dismiss = () => {
    onChange({ rowMenu: null, recording: false })
  }
  return (
    <FeatureRowMenu
      target={target}
      feature={feature}
      pinned={workspace.layout.favorites.includes(feature.id)}
      enabled={!workspace.layout.disabledFeatures.includes(feature.id)}
      hotkey={workspace.layout.hotkeys[feature.id] ?? null}
      recording={recording}
      onTogglePinned={() => {
        workspace.togglePin(feature.id)
      }}
      onSetEnabled={(enabled) => {
        workspace.setFeatureEnabled(feature.id, enabled)
      }}
      onStartRecording={() => {
        onChange({ recording: true })
      }}
      onStopRecording={dismiss}
      onSetHotkey={(hotkey) => {
        workspace.setHotkey(feature.id, hotkey)
      }}
      onDismiss={dismiss}
    />
  )
}
