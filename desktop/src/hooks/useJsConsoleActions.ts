import { useCallback } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, reactotronReverse, runAction } from "@/lib/daemon"
import { reloadMessage, type ReloadStep } from "@/lib/js-console-actions"
import type { Device } from "@/lib/wire"

export interface JsConsoleActions {
  /** Open the device's route to Metro, then look for targets again. */
  reverse: () => void
  /** Reload the JS bundle, through the device if the runtime refuses. */
  reload: () => void
}

/**
 * The two things this pane does through the daemon, and what to say about how
 * they went.
 *
 * Gathered out of the pane the way `useReactotronActions` is: a pane that both
 * renders a feed and knows which registry action stands in for a refused
 * `Page.reload` is doing two jobs, and the pane was at oxlint's dependency
 * ceiling saying so.
 */
export function useJsConsoleActions(args: {
  device: Device | null
  port: number
  reloadJs: () => Promise<ReloadStep>
  refresh: () => void
}): JsConsoleActions {
  const { show } = useNotifications()
  const { device, port, reloadJs, refresh } = args

  const reverse = useCallback(() => {
    const serial = device?.serial
    if (serial === undefined) return
    reactotronReverse([serial], port).then(
      () => {
        show({ message: `Forwarded port ${String(port)} to the device.`, ok: true })
        refresh()
      },
      (thrown: unknown) => {
        show({ message: asDaemonError(thrown).message, ok: false })
      },
    )
  }, [device, port, refresh, show])

  const reload = useCallback(() => {
    void (async () => {
      const step = await reloadJs()
      // Hermes does not always implement `Page.reload`. The Mac falls back to
      // the device's own reload keys — which is `reload-js` in the registry,
      // the very same `input keyevent 46 46` — rather than reporting a failure
      // someone can do nothing about.
      if (step === "done" || device === null) {
        show({ message: reloadMessage(step, null), ok: step === "done" })
        return
      }
      const viaDevice = await runAction({ featureId: "reload-js", serial: device.serial }).then(
        (result) => ({ ok: result.ok }),
        () => ({ ok: false }),
      )
      show({ message: reloadMessage(step, viaDevice), ok: viaDevice.ok })
    })()
  }, [device, reloadJs, show])

  return { reverse, reload }
}
