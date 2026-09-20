import { useCallback, useMemo } from "react"

import { consoleJson, exportFileName } from "@/lib/console-export"
import type { ConsoleRow } from "@/lib/console-feed"
import { asDaemonError, copyText, exportText } from "@/lib/daemon"
import { useNotifications } from "@/hooks/useNotifications"

export interface ConsoleExport {
  /** False when there is nothing to write, which disables the menu. */
  enabled: boolean
  saveAsJson: () => void
  copyToClipboard: () => void
}

/**
 * Export the console, as the Mac's two menu items do.
 *
 * **What it writes is exactly what the feed is showing** — the level picker and
 * the text filter both apply, in display order. That is the Mac's rule and it
 * is the useful one: someone who has narrowed a noisy console down to the six
 * lines that matter is exporting those six, not the thousand behind them.
 */
export function useConsoleExport(shown: readonly ConsoleRow[]): ConsoleExport {
  const { show } = useNotifications()
  const json = useMemo(() => consoleJson(shown), [shown])
  const count = shown.length

  const saveAsJson = useCallback(() => {
    exportText(exportFileName(new Date()), json).then(
      (path) => {
        show({ message: `Exported ${count.toLocaleString()} entries to ${path}`, ok: true })
      },
      (thrown: unknown) => {
        show({ message: `Export failed: ${asDaemonError(thrown).message}`, ok: false })
      },
    )
  }, [json, count, show])

  const copyToClipboard = useCallback(() => {
    copyText(json).then(
      () => {
        show({ message: `Copied ${count.toLocaleString()} entries as JSON`, ok: true })
      },
      (thrown: unknown) => {
        show({ message: `Copy failed: ${asDaemonError(thrown).message}`, ok: false })
      },
    )
  }, [json, count, show])

  return { enabled: count > 0, saveAsJson, copyToClipboard }
}
