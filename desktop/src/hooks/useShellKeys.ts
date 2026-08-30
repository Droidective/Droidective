import { useCallback, useEffect } from "react"
import { useFeatureHotkeys } from "@/hooks/useFeatureHotkeys"
import { useMenuCommands } from "@/hooks/useMenuCommands"
import { useRunFeature } from "@/hooks/useRunFeature"
import { useShellShortcuts } from "@/hooks/useShellShortcuts"
import { useTerminalCommands } from "@/hooks/useTerminalCommands"
import { useTray } from "@/hooks/useTray"
import type { SidebarModeController } from "@/hooks/useSidebarMode"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import type { Device, FeatureSummary } from "@/lib/wire"

/**
 * Every key and menu command the window answers, in the order that matters.
 *
 * The shell's own shortcuts are installed first and mark themselves handled, so
 * a per-feature binding can never shadow Close Tab — and `resolveHotkey` refuses
 * the shell's combinations outright, so the guarantee does not rest on listener
 * order either.
 *
 * The native menu is here too, because it is the same set of commands reached a
 * different way: a menu click and its accelerator have to do the same thing, and
 * two call sites is how they come to differ.
 */
export function useShellKeys({
  activeTab,
  workspace,
  sidebar,
  features,
  device,
  packageId,
  onPalette,
  onSettings,
}: {
  activeTab: string | null
  workspace: WorkspaceController
  sidebar: SidebarModeController
  features: FeatureSummary[]
  device: Device | null
  packageId: string | null
  onPalette: () => void
  onSettings: () => void
}): void {
  useShellShortcuts({
    activeTab,
    onClose: workspace.close,
    onActivateIndex: workspace.activateIndex,
    onSplit: workspace.split,
    onPalette,
    onSettings,
    onToggleSidebar: sidebar.toggle,
    onZoom: workspace.zoom,
  })

  const run = useRunFeature({ device, packageId })

  useFeatureHotkeys({
    bindings: workspace.layout.hotkeys,
    panelHotkey: workspace.layout.quickPanelHotkey,
    features,
    onRun: run,
    onOpen: workspace.open,
  })

  // A screen the panel picked, handed over through storage. See `openInApp`.
  usePanelRequests(workspace.open)

  // The tray is a third way to reach these same commands, so it dispatches
  // from here for the reason the menu does: two call sites is how a click and
  // its keystroke come to do different things.
  useTray({
    device,
    features,
    chosen: workspace.layout.trayItems,
    favorites: workspace.layout.favorites,
    disabled: workspace.layout.disabledFeatures,
    onRun: run,
    onOpen: workspace.open,
  })

  const { open } = workspace
  useMenuCommands({
    workspace,
    sidebar,
    features,
    terminal: useTerminalCommands(),
    onPalette,
    onSettings,
    onOpenTerminal: useCallback(() => {
      open("terminal")
    }, [open]),
  })
}

/**
 * A screen the Quick Actions panel asked this window to open.
 *
 * The panel is a second webview of the same origin, so it writes the request to
 * `localStorage` and the `storage` event delivers it here — which is the one
 * cross-window channel that works whether this window was hidden, minimised or
 * simply behind something. The value carries a timestamp so asking for the same
 * screen twice is two events rather than one.
 */
function usePanelRequests(open: (id: string) => void): void {
  useEffect(() => {
    const onStorage = (event: StorageEvent) => {
      if (event.key !== "droidective.openFeature" || event.newValue === null) return
      const id = event.newValue.slice(event.newValue.indexOf(":") + 1)
      if (id !== "") open(id)
    }
    globalThis.addEventListener("storage", onStorage)
    return () => {
      globalThis.removeEventListener("storage", onStorage)
    }
  }, [open])
}
