import { useEffect, useMemo } from "react"

import { useWindows } from "@/hooks/useWindows"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import { setTabPinState } from "@/lib/daemon-host"
import { onCloseFeatureRequest } from "@/lib/daemon-windows"
import { HOME_TAB } from "@/lib/layout"
import { activeTab, isPinned } from "@/lib/workspace"

/**
 * The two things the window menu needs, and the one thing another window can
 * ask of this one.
 *
 * Together because they are two halves of the same story: this window opens
 * others, and others can ask it to give an exclusive feature up. Take Over
 * closes the tab *here* before the asking window starts its own, which is what
 * keeps two scrcpy sessions off one device.
 */
export function useWindowMenu(
  workspace: WorkspaceController,
  serial: string | null,
): { onNewWindow: (serial: string | null) => void; serial: string | null } {
  const windows = useWindows()
  const { close } = workspace
  useTabPinLabel(workspace)

  useEffect(() => {
    let live = true
    let unlisten: (() => void) | null = null
    void onCloseFeatureRequest((feature) => {
      close(feature)
    }).then(
      (stop) => {
        if (live) unlisten = stop
        else stop()
      },
      () => {
        // Without the listener a take-over waits for the owning window to be
        // closed by hand, which is what happened before it existed.
      },
    )
    return () => {
      live = false
      unlisten?.()
    }
  }, [close])

  return useMemo(
    () => ({ onNewWindow: windows.newWindow, serial }),
    [windows.newWindow, serial],
  )
}

/**
 * Keeps Tab ▸ Pin Tab reading right for whatever tab is in front.
 *
 * The row's label lives in the native menu (`src-tauri/src/menu.rs`) and the
 * state it describes lives up here, so it has to be pushed down; the Mac's item
 * reads `AppState` directly and needs none of this. Home is greyed out rather
 * than relabelled — it rides the strip's own button, so there is no chip to
 * mark.
 */
function useTabPinLabel(workspace: WorkspaceController): void {
  const active = activeTab(workspace.workspace)
  const pinned = active !== null && isPinned(workspace.workspace, active)
  useEffect(() => {
    const enabled = active !== null && active !== HOME_TAB
    void setTabPinState(pinned, enabled).catch(() => {
      // A menu that failed to relabel is not worth surfacing: the row still
      // toggles, it just reads "Pin Tab" for a tab that is already pinned.
    })
  }, [active, pinned])
}
