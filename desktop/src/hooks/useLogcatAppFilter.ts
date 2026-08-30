import { useCallback, useState } from "react"
import { useLogcatApp } from "@/hooks/useLogcatApp"
import { asDaemonError, foregroundApp } from "@/lib/daemon"
import { streamPid, type AppFilter } from "@/lib/logcat-app"

export interface LogcatAppFilter {
  /** What the log is narrowed to right now, for the toolbar to say. */
  filter: AppFilter
  /** The pid the subscription should carry, or null for the whole device. */
  pid: number | null
  /** Whether narrowing is switched on at all. */
  narrowed: boolean
  setNarrowed: (narrowed: boolean) => void
  /** The Mac's "Use app on device screen": adopt whatever is in front. */
  useForegroundApp: () => void
}

/**
 * The log's app filter, wired to the app selection the rest of this UI uses.
 *
 * A hook rather than state inside the pane so `LogcatPane` stays a rendering
 * job: what is worth reading there is the feed, not four pieces of bookkeeping
 * about which process it is following.
 *
 * Narrowing is **opt-in**. The log opens on the whole device as the Mac's does,
 * and only follows the chosen app once someone asks — a screen that silently
 * filtered itself because an app happened to be selected in another tab would
 * be hiding lines nobody asked it to hide.
 */
export function useLogcatAppFilter({
  serial,
  packageId,
  onSelectPackage,
  onError,
}: {
  serial: string | null
  packageId: string | null
  onSelectPackage: (packageId: string | null) => void
  onError: (message: string) => void
}): LogcatAppFilter {
  const [narrowed, setNarrowed] = useState(false)
  const filter = useLogcatApp(serial, narrowed ? packageId : null)

  const useForegroundApp = useCallback(() => {
    if (serial === null) return
    void foregroundApp(serial).then(
      (answer) => {
        // Nothing in front is an answer, not a failure — the launcher is there
        // more often than any app is — so nothing happens rather than an error
        // about it. The daemon omits the key entirely, hence undefined.
        if (answer.packageId === undefined) return
        onSelectPackage(answer.packageId)
        setNarrowed(true)
      },
      (thrown: unknown) => {
        onError(asDaemonError(thrown).message)
      },
    )
  }, [serial, onSelectPackage, onError])

  return { filter, pid: streamPid(filter), narrowed, setNarrowed, useForegroundApp }
}
