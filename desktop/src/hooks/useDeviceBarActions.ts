import { useCallback, useEffect, useState } from "react"
import type { TailscaleMenu } from "@/components/DeviceMenuSections"
import type { DeviceSheet } from "@/components/DeviceSheets"
import { useNotifications } from "@/hooks/useNotifications"
import {
  asDaemonError,
  connectTailscale,
  disconnectWireless,
  emulatorAction,
  emulators,
  phoneSetupOffer,
  prepareForTailscale,
  tailscaleStatus,
} from "@/lib/daemon"
import { canPrepareForTailscale } from "@/lib/tailnet"
import { isReady } from "@/lib/targets"
import type {
  Avd,
  Device,
  PhoneSetupOffer,
  TailscalePeer,
  TailscaleStatus,
} from "@/lib/wire"

/**
 * The two things the device bar can do to the world: start an AVD, and drop a
 * wireless connection.
 *
 * Together — with the phone set-up probe and the Tailscale section below —
 * because they are the bar's only daemon calls, and keeping them here leaves
 * the bar itself about layout. The AVD list is re-read whenever the
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
  /** What the menu offers the selected phone — install, update or set up — or null. */
  offer: PhoneSetupOffer | null
  /** Ask again — the device menu does on every open, as the Mac's does. */
  reprobe: () => void
  /** What the sheet's last read says to offer, so the entry changes at once. */
  report: (serial: string, offer: PhoneSetupOffer | null) => void
}

/**
 * What the device menu offers for Droidective for Android — the Mac's
 * `probePhoneSetup`.
 *
 * Background, so it stays out of the Command Log, and a failed read just
 * leaves the entry out: a menu is no place to report one. The answer is kept
 * with the serial it was asked about, so a reply for the previous device can
 * never put the entry under the next one.
 */
export function usePhoneSetupProbe(selected: Device | null): PhoneSetupProbe {
  const candidate =
    selected !== null && selected.platform === "android" && isReady(selected)
      ? selected.serial
      : null
  const [answer, setAnswer] = useState<{ serial: string; offer: PhoneSetupOffer } | null>(null)
  const [generation, setGeneration] = useState(0)

  useEffect(() => {
    if (candidate === null) return
    let live = true
    phoneSetupOffer(candidate).then(
      (reply) => {
        if (live) setAnswer(reply.offer === null ? null : { serial: candidate, offer: reply.offer })
      },
      () => {
        if (live) setAnswer(null)
      },
    )
    return () => {
      live = false
    }
  }, [candidate, generation])

  const reprobe = useCallback(() => {
    setGeneration((value) => value + 1)
  }, [])

  const report = useCallback((serial: string, offer: PhoneSetupOffer | null) => {
    setAnswer(offer === null ? null : { serial, offer })
  }, [])

  const offer = candidate !== null && answer?.serial === candidate ? answer.offer : null
  return { offer, reprobe, report }
}

export interface Tailscale {
  /** Null until the first read, and whenever a read fails. */
  status: TailscaleStatus | null
  /** Read again — the device menu does on every open, as the Mac's does. */
  reprobe: () => void
  /** `adb connect` to one peer, then say what adb said. */
  connect: (peer: TailscalePeer) => void
  /** `adb tcpip 5555` on a cabled phone, after the menu's confirmation. */
  prepare: (device: Device) => void
}

/**
 * The device menu's Tailscale section — the Mac's `refreshTailscale` and its
 * two verbs.
 *
 * Re-read when the device set changes (a phone that just connected stops
 * being offered) and on every menu open, always as a background call: the
 * daemon runs `adb devices` for it, and a menu opening is not something the
 * user asked to have logged. A failed read just leaves the section out, as the
 * phone set-up probe does — a menu is no place to report one.
 */
export function useTailscale(
  devices: readonly Device[],
  onDevicesChanged: () => Promise<void>,
): Tailscale {
  const { show } = useNotifications()
  const [status, setStatus] = useState<TailscaleStatus | null>(null)
  const [generation, setGeneration] = useState(0)

  const fingerprint = devices.map((device) => `${device.serial}:${device.state}`).join(",")
  useEffect(() => {
    let live = true
    tailscaleStatus().then(
      (next) => {
        if (live) setStatus(next)
      },
      () => {
        if (live) setStatus(null)
      },
    )
    return () => {
      live = false
    }
  }, [fingerprint, generation])

  const reprobe = useCallback(() => {
    setGeneration((value) => value + 1)
  }, [])

  const report = useCallback(
    async (call: () => Promise<{ ok: boolean; message: string }>, failurePrefix: string) => {
      try {
        const result = await call()
        // Important, as the Mac marks it: a device arriving or switching
        // transport is worth finding again in the panel.
        show({ message: result.message, ok: result.ok, important: true })
      } catch (thrown) {
        show({ message: `${failurePrefix}: ${asDaemonError(thrown).message}`, ok: false })
      } finally {
        // A refresh that fails leaves the list as the stream last sent it,
        // which is still the truth; there is nothing to add to the toast.
        await onDevicesChanged().catch(() => null)
        reprobe()
      }
    },
    [show, onDevicesChanged, reprobe],
  )

  const connect = useCallback(
    (peer: TailscalePeer) => {
      void report(() => connectTailscale(peer), peer.name)
    },
    [report],
  )

  const prepare = useCallback(
    (device: Device) => {
      void report(() => prepareForTailscale(device.serial), device.label)
    },
    [report],
  )

  return { status, reprobe, connect, prepare }
}

/**
 * The menu's Tailscale section from what the daemon read, or null without a
 * Tailscale CLI. "Prepare … for Tailscale…" names the selected phone, and only
 * a cabled one (`canPrepareForTailscale`); choosing it opens the served
 * warning rather than running anything.
 */
export function tailscaleMenu(
  tailscale: Pick<Tailscale, "status" | "connect">,
  selected: Device | null,
  onSheet: (sheet: DeviceSheet) => void,
): TailscaleMenu | null {
  const status = tailscale.status
  if (status?.installed !== true) return null
  const warning = status.prepareWarning
  return {
    notice: status.notice,
    peers: status.peers,
    onConnect: tailscale.connect,
    prepare: canPrepareForTailscale(selected)
      ? {
          name: selected.label,
          onSelect: () => {
            onSheet({ kind: "tailscale-prepare", device: selected, warning })
          },
        }
      : null,
  }
}
