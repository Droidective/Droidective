import { useCallback, useEffect, useState } from "react"
import { useNotifications } from "@/hooks/useNotifications"
import {
  asDaemonError,
  disconnectWireless,
  emulatorAction,
  emulators,
  phoneSetupStatus,
} from "@/lib/daemon"
import { isReady } from "@/lib/targets"
import type { Avd, Device, PhoneSetupStatus } from "@/lib/wire"

/**
 * The two things the device bar can do to the world: start an AVD, and drop a
 * wireless connection.
 *
 * Together — with the phone set-up probe below — because they are the bar's
 * only daemon calls, and keeping them here leaves the bar itself about layout. The AVD list is re-read whenever the
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

export interface PhoneSetupProbe {
  /** The selected phone has Droidective for Android with set-up still to do. */
  needsSetup: boolean
  /** Ask again — the device menu does on every open, as the Mac's does. */
  reprobe: () => void
  /** A status the sheet read, so the entry goes the moment set-up is done. */
  report: (serial: string, status: PhoneSetupStatus) => void
}

/**
 * Whether the device menu offers "Set Up Droidective on This Phone…" — the
 * Mac's `probePhoneSetup`.
 *
 * Marked background, so it stays out of the Command Log, and a failed read
 * just leaves the entry out: a menu is no place to report one. The answer is
 * kept with the serial it was asked about, so a reply for the previous device
 * can never put the entry under the next one.
 */
export function usePhoneSetupProbe(selected: Device | null): PhoneSetupProbe {
  const candidate =
    selected !== null && selected.platform === "android" && isReady(selected)
      ? selected.serial
      : null
  const [needsFor, setNeedsFor] = useState<string | null>(null)
  const [generation, setGeneration] = useState(0)

  useEffect(() => {
    if (candidate === null) return
    let live = true
    phoneSetupStatus(candidate, true).then(
      (status) => {
        if (live) setNeedsFor(status.needsSetup ? candidate : null)
      },
      () => {
        if (live) setNeedsFor(null)
      },
    )
    return () => {
      live = false
    }
  }, [candidate, generation])

  const reprobe = useCallback(() => {
    setGeneration((value) => value + 1)
  }, [])

  const report = useCallback((serial: string, status: PhoneSetupStatus) => {
    setNeedsFor(status.needsSetup ? serial : null)
  }, [])

  return { needsSetup: candidate !== null && needsFor === candidate, reprobe, report }
}
