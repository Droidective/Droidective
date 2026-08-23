import { useCallback, useState } from "react"
import { asDaemonError, copyText, exportText, reactotronReverse } from "@/lib/daemon"
import { copyEventsAsJson } from "@/lib/reactotron-copy"
import type { TimelineRow } from "@/lib/reactotron-rows"
import type { Device, ReactotronReverseResponse } from "@/lib/wire"

export interface ReactotronActions {
  /** The last thing that went right, worth a line above the rows. */
  notice: string | null
  /** The last thing that went wrong. */
  failure: string | null
  /** The last tunnel attempt, so its per-device outcome stays on screen. */
  tunnel: ReactotronReverseResponse | null
  openTunnel: () => void
  exportShown: () => void
  copyShown: () => void
  report: (outcome: { ok: boolean; message: string }) => void
}

/**
 * The things the pane can *do*, and what to say about how they went.
 *
 * Gathered out of the pane because they share one pair of notice/failure slots
 * and nothing else in the pane touches them — and because a pane that both
 * renders a feed and knows how to name an export file is doing two jobs.
 */
export function useReactotronActions(args: {
  device: Device | null
  /** The port the relay reported, so a tunnel goes where it is listening. */
  port: number | null
  /** What is currently shown — a filter narrows the export as well as the view. */
  visible: readonly TimelineRow[]
}): ReactotronActions {
  const [notice, setNotice] = useState<string | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  const [tunnel, setTunnel] = useState<ReactotronReverseResponse | null>(null)
  const { device, port, visible } = args

  const report = useCallback((outcome: { ok: boolean; message: string }) => {
    if (outcome.ok) {
      setNotice(outcome.message)
      setFailure(null)
    } else {
      setFailure(outcome.message)
    }
  }, [])

  const openTunnel = useCallback(() => {
    if (device === null) return
    setFailure(null)
    reactotronReverse([device.serial], port).then(setTunnel, (thrown: unknown) => {
      setFailure(asDaemonError(thrown).message)
    })
  }, [device, port])

  // Both verbs hand over the same thing — the raw wire commands of what is
  // shown — so a saved file and a pasted clipboard can be read by one script.
  const exportShown = useCallback(() => {
    setFailure(null)
    const stamp = new Date().toISOString().replaceAll(/[:.]/gu, "-").slice(0, 19)
    exportText(`reactotron_${stamp}.json`, copyEventsAsJson(visible)).then(
      (path) => {
        setNotice(`Exported ${visible.length.toLocaleString()} events to ${path}`)
      },
      (thrown: unknown) => {
        setFailure(asDaemonError(thrown).message)
      },
    )
  }, [visible])

  const copyShown = useCallback(() => {
    setFailure(null)
    copyText(copyEventsAsJson(visible)).then(
      () => {
        setNotice(`Copied ${visible.length.toLocaleString()} events as JSON`)
      },
      (thrown: unknown) => {
        setFailure(asDaemonError(thrown).message)
      },
    )
  }, [visible])

  return { notice, failure, tunnel, openTunnel, exportShown, copyShown, report }
}
