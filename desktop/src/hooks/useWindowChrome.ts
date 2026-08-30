import { useEffect } from "react"
import { useSidebarMode, type SidebarModeController } from "@/hooks/useSidebarMode"
import { useWorkspace, type WorkspaceController } from "@/hooks/useWorkspace"
import { useZoom } from "@/hooks/useZoom"
import { setBackgroundMode } from "@/lib/daemon"
import type { FeatureSummary } from "@/lib/wire"
import { activeTab } from "@/lib/workspace"

export interface WindowChrome {
  workspace: WorkspaceController
  sidebar: SidebarModeController
  /**
   * The feature in the focused tab, or null for Home and the app's own screens.
   *
   * The device bar needs it: whether Run on all is offered at all is the
   * registry's answer about the tab in front — `AppState.activeFeatureSupportsRunAll`
   * on the Mac — which is why it is resolved here rather than inside the shell.
   */
  focusedFeature: FeatureSummary | null
}

/**
 * The window's own state: its tabs and layout, its sidebar mode, and its zoom.
 *
 * One hook because they are one thing — what this window looks like — and
 * because two of the three are read *above* the workspace shell, by the device
 * bar. Applying the zoom is a side effect on the document, so it belongs with
 * the state that decides it rather than with the layout that renders under it.
 */
export function useWindowChrome(features: FeatureSummary[]): WindowChrome {
  const workspace = useWorkspace(features)
  const sidebar = useSidebarMode(workspace.layout.sidebarAutoHide, workspace.setSidebarAutoHide)
  useZoom(workspace.layout.zoomStep)

  // The preference is remembered here; the decision it drives — whether the
  // close button hides the window or quits — is taken in the Rust process
  // before the page is asked anything, so it is mirrored there rather than
  // read at the moment of the click.
  const keepRunning = workspace.layout.keepRunningInBackground
  useEffect(() => {
    void setBackgroundMode(keepRunning).catch(() => {
      // Outside a Tauri webview, which is a test. Nothing to say about it.
    })
  }, [keepRunning])

  const focused = activeTab(workspace.workspace)
  return {
    workspace,
    sidebar,
    focusedFeature: features.find((feature) => feature.id === focused) ?? null,
  }
}
