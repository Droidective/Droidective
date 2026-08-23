import { useEffect, useState } from "react"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, disconnectWireless, emulatorAction, emulators } from "@/lib/daemon"
import type { Avd, Device } from "@/lib/wire"

/**
 * The two things the device bar can do to the world: start an AVD, and drop a
 * wireless connection.
 *
 * Together because they are the bar's only daemon calls, and keeping them here
 * leaves the bar itself about layout. The AVD list is re-read whenever the
 * device set changes, as the Mac's `.task(id:)` on the joined serials does: an
 * AVD that just booted is a device now, so it should stop being offered as one
 * to launch.
 */
export function useDeviceBarActions(devices: readonly Device[]): {
  avds: Avd[]
  launch: (avd: Avd) => void
  disconnect: (device: Device) => void
} {
  const { show } = useNotifications()
  const [avds, setAvds] = useState<Avd[]>([])

  const fingerprint = devices.map((device) => device.serial).join(",")
  useEffect(() => {
    let cancelled = false
    void (async () => {
      try {
        const response = await emulators()
        if (!cancelled) setAvds(response.avds)
      } catch {
        // A machine with no emulator binary is not an error worth reporting on
        // the device bar; the Emulators screen explains it properly.
        if (!cancelled) setAvds([])
      }
    })()
    return () => {
      cancelled = true
    }
  }, [fingerprint])

  return {
    avds,
    launch: (avd: Avd) => {
      void (async () => {
        try {
          const result = await emulatorAction({ action: "launch", avd: avd.name })
          show({ message: result.message, ok: result.ok })
        } catch (thrown) {
          show({ message: asDaemonError(thrown).message, ok: false })
        }
      })()
    },
    disconnect: (device: Device) => {
      void (async () => {
        try {
          const result = await disconnectWireless(device.serial)
          // Important: a device leaving is worth finding again in the panel.
          show({ message: result.message, ok: result.ok, important: true })
        } catch (thrown) {
          show({ message: `${device.label}: ${asDaemonError(thrown).message}`, ok: false })
        }
      })()
    },
  }
}
