import { useCallback, useEffect, useRef, useState } from "react"
import {
  asDaemonError,
  daemonStatus,
  listDevices,
  listFeatures,
  onDaemonStatus,
  watchDevices,
  type Subscription,
} from "@/lib/daemon"
import type { DaemonError, DaemonStatus, Device, FeatureSummary } from "@/lib/wire"

export interface Session {
  status: DaemonStatus
  devices: Device[]
  /** False until the first device snapshot lands, so "none" reads as "none". */
  devicesLoaded: boolean
  features: FeatureSummary[]
  selected: Device | null
  select: (serial: string) => void
  error: DaemonError | null
}

/**
 * The daemon-backed state the whole window shares.
 *
 * The device list arrives two ways on purpose: one `list_devices` call for the
 * state at startup, then the `devices` stream for changes. The stream alone is
 * not enough — it publishes on change, so a client that connects while nothing
 * is happening would wait indefinitely for its first list.
 */
export function useSession(): Session {
  const [status, setStatus] = useState<DaemonStatus>({ state: "starting" })
  const [devices, setDevices] = useState<Device[]>([])
  const [devicesLoaded, setDevicesLoaded] = useState(false)
  const [features, setFeatures] = useState<FeatureSummary[]>([])
  const [error, setError] = useState<DaemonError | null>(null)
  const [serial, setSerial] = useState<string | null>(null)

  // StrictMode runs effects twice in development. Without this the second run
  // opens a second device subscription and the first is never torn down.
  const subscription = useRef<Subscription | null>(null)

  useEffect(() => {
    let cancelled = false

    const load = async () => {
      try {
        const [loadedFeatures, loadedDevices] = await Promise.all([listFeatures(), listDevices()])
        if (cancelled) return
        setFeatures(loadedFeatures)
        setDevices(loadedDevices)
        setDevicesLoaded(true)
        const live = await watchDevices((update) => {
          // A devices batch is the whole list, not an addition — and an empty
          // one is how the daemon says everything was unplugged.
          if (update.event === "batch") {
            setDevices(update.items)
            setDevicesLoaded(true)
          }
        })
        if (cancelled) {
          void live.stop()
          return
        }
        subscription.current = live
      } catch (thrown) {
        if (!cancelled) setError(asDaemonError(thrown))
      }
    }

    const start = async () => {
      const unlisten = await onDaemonStatus((next) => {
        if (cancelled) return
        setStatus(next)
        if (next.state === "ready") void load()
      })
      // The daemon may already have come up before this effect ran; the event
      // fires once and would have been missed.
      const current = await daemonStatus()
      if (cancelled) {
        unlisten()
        return
      }
      setStatus(current)
      if (current.state === "ready") void load()
      return unlisten
    }

    const pending = start()
    return () => {
      cancelled = true
      void pending.then((unlisten) => unlisten?.())
      void subscription.current?.stop()
      subscription.current = null
    }
  }, [])

  // Keep a valid selection: adopt the first device, and let go of one that
  // has been unplugged rather than acting on a serial that is gone.
  useEffect(() => {
    setSerial((current) => {
      if (current !== null && devices.some((device) => device.serial === current)) return current
      return devices.find((device) => device.state === "device")?.serial ?? devices[0]?.serial ?? null
    })
  }, [devices])

  const select = useCallback((next: string) => {
    setSerial(next)
  }, [])

  return {
    status,
    devices,
    devicesLoaded,
    features,
    selected: devices.find((device) => device.serial === serial) ?? null,
    select,
    error,
  }
}
