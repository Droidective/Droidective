import { DeviceBar } from "@/components/DeviceBar"
import type { Session } from "@/hooks/useSession"
import type { SidebarModeController } from "@/hooks/useSidebarMode"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import { effectiveRunOnAll, showsRunAll } from "@/lib/targets"
import type { FeatureSummary } from "@/lib/wire"

/**
 * The device bar, wired to the session and the workspace.
 *
 * Split from the bar itself for the reason `TabContextMenu` is split from
 * `TabMenu`: the bar renders, this decides. Whether Run on all is offered at
 * all is the registry's answer about the focused tab, which is why the focused
 * feature reaches here rather than the bar working it out.
 */
export function DeviceBarHost({
  session,
  workspace,
  focusedFeature,
  sidebar,
}: {
  session: Session
  workspace: WorkspaceController
  focusedFeature: FeatureSummary | null
  sidebar: SidebarModeController
}) {
  const runOnAll = workspace.layout.runOnAll
  return (
    <DeviceBar
      sidebarAutoHide={sidebar.mode.autoHide}
      onToggleSidebarMode={sidebar.pressButton}
      devices={session.devices}
      devicesLoaded={session.devicesLoaded}
      selected={session.selected}
      onSelect={session.select}
      onRefresh={session.refresh}
      onOpenFeature={workspace.open}
      showsRunAll={showsRunAll(session.devices, focusedFeature)}
      runOnAll={runOnAll}
      onRunOnAll={workspace.setRunOnAll}
      // The Mac pins the device pill while a fan-out is on: the selection is
      // one of the targets, so changing it mid-run would change what ran.
      deviceLocked={effectiveRunOnAll(runOnAll, focusedFeature)}
    />
  )
}
