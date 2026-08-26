import { useEffect, useState } from "react"

import { watchDevices, type Subscription } from "@/lib/daemon"
import type { Device, StreamUpdate } from "@/lib/wire"

/**
 * Every connected device, for a screen that is not scoped to the bar's one.
 *
 * Most panes take a `device` prop, because most panes act on the selection.
 * The two that do not — the Mirror Wall picks its own devices, and Wireless ADB
 * is about the devices themselves — need the whole list, and threading it down
 * through the pane tree would be prop-drilling a value every other pane would
 * ignore.
 *
 * A second subscription to `devices` is cheap: it is a snapshot topic and the
 * daemon serves every one of them from the same `DeviceMonitor`.
 */
export function useConnectedDevices(): Device[] {
  const [devices, setDevices] = useState<Device[]>([])

  useEffect(() => {
    let cancelled = false
    let subscription: Subscription | null = null

    watchDevices((update: StreamUpdate<Device>) => {
      // A devices batch is the whole list, not an addition — including the
      // empty one that says everything was unplugged.
      if (update.event === "batch") setDevices(update.items)
    }).then(
      (handle) => {
        if (cancelled) {
          void handle.stop()
          return
        }
        subscription = handle
      },
      () => {
        // A device list a pane cannot get is not worth its own error state:
        // every screen using this already says something for "nothing
        // connected", which is where someone is looking.
      },
    )

    return () => {
      cancelled = true
      void subscription?.stop()
    }
  }, [])

  return devices
}
