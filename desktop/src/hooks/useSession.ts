import { useCallback, useEffect, useMemo, useRef, useState } from "react"

import {
  currentWindowLabel,
  loadLayout,
  loadWindowLayout,
  requestedSerial,
  saveWindowLayout,
} from "@/lib/layout"
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
  /**
   * Ask adb again, now.
   *
   * The stream publishes on change, so a device that never appears produces no
   * event to wait for — which is the situation the device bar's refresh button
   * exists for. The Mac reaches the same place by refreshing as its dropdown
   * opens.
   */
  refresh: () => Promise<void>
  error: DaemonError | null
}

/**
 * The daemon-backed state the whole window shares.
 *
 * The device list arrives two ways on purpose: one `list_devices` call for the
 * state at startup, then the `devices` stream for changes. The stream alone is
 * not enough — it publishes on change, so a client that connects while nothing
 * is happening would wait indefinitely for its first list.
 *
 * **The two loads are independent, and that is load-bearing.** They used to
 * arrive through one `Promise.all`, which handed the *slower* of them the
 * decision about when the app became usable — and on a machine whose adb server
 * is not running yet, `list_devices` is the slow one, because adb has to fork
 * that server before it can answer. That is exactly how the Linux app's first
 * launch came up with an empty sidebar and "0 features": the registry had
 * answered in milliseconds and nothing rendered it. The device bar already has
 * a "looking for devices" state to sit in; the sidebar has no reason to wait in
 * it too.
 */
export function useSession(): Session {
  const [status, setStatus] = useState<DaemonStatus>({ state: "starting" })
  const [devices, setDevices] = useState<Device[]>([])
  const [devicesLoaded, setDevicesLoaded] = useState(false)
  const [features, setFeatures] = useState<FeatureSummary[]>([])
  const [error, setError] = useState<DaemonError | null>(null)
  const [serial, setSerial] = useWindowSerial()

  // StrictMode runs effects twice in development. Without this the second run
  // opens a second device subscription and the first is never torn down.
  const subscription = useRef<Subscription | null>(null)

  useEffect(() => {
    let cancelled = false
    const alive = () => !cancelled

    // Once. The daemon can go ready between the listener being registered and
    // `daemonStatus()` answering, in which case both paths below call this —
    // and a second `loadDevices` opens a second subscription that nothing
    // stops, because only the last one is kept.
    let loading = false
    const load = () => {
      if (loading) return
      loading = true
      void loadFeatures({ alive, setFeatures, setError })
      void loadDevices({ alive, setDevices, setDevicesLoaded, setError, subscription })
    }

    const start = async () => {
      const unlisten = await onDaemonStatus((next) => {
        if (cancelled) return
        setStatus(next)
        if (next.state === "ready") load()
      })
      // The daemon may already have come up before this effect ran; the event
      // fires once and would have been missed.
      const current = await daemonStatus()
      if (cancelled) {
        unlisten()
        return
      }
      setStatus(current)
      if (current.state === "ready") load()
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
  }, [devices, setSerial])

  const select = useCallback(
    (next: string) => {
      setSerial(next)
    },
    [setSerial],
  )

  const refresh = useCallback(async () => {
    try {
      setDevices(await listDevices())
      setDevicesLoaded(true)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [])

  return {
    status,
    devices,
    devicesLoaded,
    features,
    selected: devices.find((device) => device.serial === serial) ?? null,
    select,
    refresh,
    error,
  }
}

/** `alive` is the effect's own teardown flag: nothing is written after it. */
interface Alive {
  alive: () => boolean
  setError: (error: DaemonError) => void
}

async function loadFeatures({
  alive,
  setFeatures,
  setError,
}: Alive & { setFeatures: (features: FeatureSummary[]) => void }): Promise<void> {
  try {
    const loaded = await listFeatures()
    if (alive()) setFeatures(loaded)
  } catch (thrown) {
    if (alive()) setError(asDaemonError(thrown))
  }
}

async function loadDevices({
  alive,
  setDevices,
  setDevicesLoaded,
  setError,
  subscription,
}: Alive & {
  setDevices: (devices: Device[]) => void
  setDevicesLoaded: (loaded: boolean) => void
  subscription: { current: Subscription | null }
}): Promise<void> {
  try {
    const loaded = await listDevices()
    if (!alive()) return
    setDevices(loaded)
    setDevicesLoaded(true)
    const live = await watchDevices((update) => {
      // A devices batch is the whole list, not an addition — and an empty one
      // is how the daemon says everything was unplugged.
      if (update.event === "batch") {
        setDevices(update.items)
        setDevicesLoaded(true)
      }
    })
    if (!alive()) {
      void live.stop()
      return
    }
    subscription.current = live
  } catch (thrown) {
    if (alive()) setError(asDaemonError(thrown))
  }
}

/**
 * The selected device, which belongs to *this* window.
 *
 * Seeded from the query string when "New Window for Device" named one, and
 * otherwise from what this window was last pointed at. Written on change
 * rather than at teardown: a window closed by the window manager gets no
 * teardown, and the Mac persists on change too.
 */
function useWindowSerial(): [string | null, React.Dispatch<React.SetStateAction<string | null>>] {
  const label = useMemo(() => currentWindowLabel(globalThis.location.search), [])
  const [serial, setSerial] = useState<string | null>(
    () =>
      requestedSerial(globalThis.location.search) ??
      loadWindowLayout(globalThis.localStorage, label, loadLayout(globalThis.localStorage)).serial,
  )

  useEffect(() => {
    const current = loadWindowLayout(
      globalThis.localStorage,
      label,
      loadLayout(globalThis.localStorage),
    )
    saveWindowLayout(globalThis.localStorage, label, { ...current, serial })
  }, [label, serial])

  return [serial, setSerial]
}
