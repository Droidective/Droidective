import { useEffect, useMemo } from "react"

import { useWindows } from "@/hooks/useWindows"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import { onCloseFeatureRequest } from "@/lib/daemon-windows"

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
