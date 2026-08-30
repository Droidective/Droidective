import { useCallback, useState } from "react"
import { useNotifications } from "@/hooks/useNotifications"
import { useTargets } from "@/hooks/useTargets"
import { asDaemonError, runAction } from "@/lib/daemon"
import { runOnTargets } from "@/lib/runner"
import type { Device, FieldValue } from "@/lib/wire"

export interface HubActions {
  /** Run one registry action with the values a hub's own controls collected. */
  run: (featureId: string, fields?: Record<string, FieldValue>) => void
  /**
   * The one action in flight, by feature id.
   *
   * Per action rather than a single busy flag, because a hub is a screen full
   * of buttons: the Mac's `ReactNativeView` keeps `runningID` for exactly this
   * reason — a shared flag would grey out every button on the screen because
   * one of them is running.
   */
  runningId: string | null
}

/**
 * Running a hub's gathered actions — the Mac's `state.run(feature:params:)`.
 *
 * A hub is a screen of controls over features that each have a registry entry,
 * so nothing here re-implements an action: it collects the values and hands
 * them to the same `run_action` route the generated `ActionForm` uses. The
 * targets are the device bar's, so Run on all applies here exactly as it does
 * to a form — which is what `supportsRunAll` on the hub members is for.
 */
export function useHubAction(device: Device | null): HubActions {
  const { show } = useNotifications()
  const { serials } = useTargets()
  const [runningId, setRunningId] = useState<string | null>(null)

  const run = useCallback(
    (featureId: string, fields?: Record<string, FieldValue>) => {
      if (serials.length === 0) {
        show({ message: "No device connected.", ok: false })
        return
      }
      setRunningId(featureId)
      void (async () => {
        try {
          const outcome = await runOnTargets(runAction, {
            featureId,
            serials,
            platform: device?.platform ?? "android",
            fields,
          })
          if (outcome !== null) {
            show({
              message: outcome.message,
              ok: outcome.ok,
              ...(outcome.copyText === null ? {} : { copyText: outcome.copyText }),
            })
          }
        } catch (thrown) {
          show({ message: asDaemonError(thrown).message, ok: false })
        } finally {
          // Only if this action is still the one showing as running — a newer
          // click on another button owns the state now, as the Mac's does.
          setRunningId((current) => (current === featureId ? null : current))
        }
      })()
    },
    [device, serials, show],
  )

  return { run, runningId }
}
