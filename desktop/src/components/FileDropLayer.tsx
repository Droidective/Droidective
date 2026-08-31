import { useMemo } from "react"

import { FileDropOverlay } from "@/components/FileDropOverlay"
import { useDropTarget } from "@/hooks/useDropTarget"
import { useFileDrop } from "@/hooks/useFileDrop"
import { useTargets } from "@/hooks/useTargets"
import type { DropContext } from "@/lib/file-drop"

/**
 * Files dropped on this window, and the overlay that says what will happen.
 *
 * Its own component so the shell keeps one line for it: everything here is
 * reading three contexts and handing the result to a hook, which inline made
 * `WorkspaceShell` about drops rather than about arranging panes.
 */
export function FileDropLayer({ activeFeature }: { activeFeature: string | null }) {
  const { serials } = useTargets()
  const { directory } = useDropTarget()

  const fingerprint = serials.join(",")
  const context = useMemo<DropContext>(
    () => ({
      activeFeature,
      explorerDirectory: directory,
      serials: fingerprint === "" ? [] : fingerprint.split(","),
    }),
    [activeFeature, directory, fingerprint],
  )

  const { over, busy } = useFileDrop(context)
  return <FileDropOverlay over={over} busy={busy} context={context} />
}
