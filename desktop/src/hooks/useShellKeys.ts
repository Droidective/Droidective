import { useCallback } from "react"
import { useFeatureHotkeys } from "@/hooks/useFeatureHotkeys"
import { useMenuCommands } from "@/hooks/useMenuCommands"
import { useRunFeature } from "@/hooks/useRunFeature"
import { useShellShortcuts } from "@/hooks/useShellShortcuts"
import { useTerminalCommands } from "@/hooks/useTerminalCommands"
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

  useFeatureHotkeys({
    bindings: workspace.layout.hotkeys,
    features,
    onRun: useRunFeature({ device, packageId }),
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
