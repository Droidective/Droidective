import { useCallback } from "react"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, runAction } from "@/lib/daemon"
import { runFields } from "@/lib/fields"
import type { Device, FeatureSummary } from "@/lib/wire"

/**
 * Running a feature with no form in front of it, and reporting what came back.
 *
 * The Mac's `AppState.run` for the quick paths — a hotkey, the menu bar, the
 * Quick Actions panel — including its two refusals: a `needsBundle` feature with
 * no app chosen, and no device attached. Both are toasts rather than silence,
 * because a shortcut that appears to do nothing is indistinguishable from a
 * shortcut that is not registered.
 */
export function useRunFeature({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}): (feature: FeatureSummary) => void {
  const { show } = useNotifications()

  return useCallback(
    (feature: FeatureSummary) => {
      if (feature.needsBundle && packageId === null) {
        show({ message: "Pick an app in Apps first.", ok: false })
        return
      }
      if (feature.needsDevice && device === null) {
        show({ message: "No device connected.", ok: false })
        return
      }
      if (feature.needsDevice && device?.state !== "device") {
        show({ message: `${device?.label ?? "The device"} is ${device?.state ?? "not ready"}.`, ok: false })
        return
      }
      void (async () => {
        try {
          const fields = runFields(feature, {}, undefined, packageId)
          const outcome = await runAction({
            featureId: feature.id,
            serial: device?.serial ?? "",
            platform: device?.platform ?? "android",
            ...(fields ? { fields } : {}),
          })
          show({
            message: outcome.message,
            ok: outcome.ok,
            ...(outcome.copyText === null ? {} : { copyText: outcome.copyText }),
            ...(outcome.revealPath === null ? {} : { revealPath: outcome.revealPath }),
          })
        } catch (thrown) {
          show({ message: asDaemonError(thrown).message, ok: false })
        }
      })()
    },
    [device, packageId, show],
  )
}
