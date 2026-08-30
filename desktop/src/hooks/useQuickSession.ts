import { useCallback, useEffect, useState } from "react"
import {
  customCommands,
  listDevices,
  listFeatures,
  runCustomCommand,
  showMainWindow,
  watchDevices,
} from "@/lib/daemon"
import { loadLayout, type LayoutState } from "@/lib/layout"
import type { CustomCommand, Device, FeatureSummary } from "@/lib/wire"

/** What the main window listens on to open a screen the panel picked. */
const OPEN_FEATURE_KEY = "droidective.openFeature"

/**
 * Everything the Quick Actions panel needs, in its own webview.
 *
 * A second window is a second page, so none of the main window's state is
 * reachable from here — this asks the daemon for the same things again. That is
 * cheap and, more to the point, correct: the panel is often summoned while the
 * main window is hidden, where its React tree is idle and its device list may
 * be minutes old.
 *
 * The layout is read straight from storage rather than subscribed to. Both
 * windows are the same origin, so it is the same `localStorage`, and the panel
 * is a short-lived screen — it reads the arrangement as it was when summoned,
 * which is what the Mac's panel does with `LayoutState` too.
 */
export interface QuickSession {
  features: FeatureSummary[]
  devices: Device[]
  commands: CustomCommand[]
  layout: LayoutState
  /** Runs a saved command, answering with what to show in the footer. */
  runCommand: (id: string) => Promise<{ message: string; ok: boolean }>
  /** Hands a screen to the main window and brings it forward. */
  openInApp: (id: string) => Promise<void>
}

export function useQuickSession(): QuickSession {
  const [features, setFeatures] = useState<FeatureSummary[]>([])
  const [devices, setDevices] = useState<Device[]>([])
  const [commands, setCommands] = useState<CustomCommand[]>([])
  const [layout] = useState<LayoutState>(() => loadLayout(globalThis.localStorage))

  useEffect(() => {
    let live = true
    void listFeatures().then((loaded) => {
      if (live) setFeatures(loaded)
    }, ignore)
    void customCommands().then((loaded) => {
      if (live) setCommands(loaded.commands)
    }, ignore)
    // Asked for once and then watched, for the reason the main window does the
    // same: the stream publishes on change, so a panel summoned while nothing
    // is happening would wait for a list that never arrives.
    void listDevices().then((loaded) => {
      if (live) setDevices(loaded)
    }, ignore)
    return () => {
      live = false
    }
  }, [])

  useEffect(() => {
    let live = true
    let stop: (() => Promise<void>) | null = null
    void watchDevices((update) => {
      if (update.event === "batch") setDevices(update.items)
    }).then((subscription) => {
      if (live) stop = subscription.stop
      else void subscription.stop()
    }, ignore)
    return () => {
      live = false
      void stop?.()
    }
  }, [])

  const runCommand = useCallback(
    async (id: string) => {
      const command = commands.find((candidate) => candidate.id === id)
      if (command === undefined) return { message: "That command is gone.", ok: false }
      const serial = devices.find((device) => device.state === "device")?.serial ?? ""
      // No bundle: the panel has no Apps tab to have chosen one in, and a
      // `{bundleId}` command says so rather than running against nothing. The
      // Mac pushes a pick-bundle interstitial here, which is on the list.
      const result = await runCustomCommand(id, serial, null)
      return { message: result.message, ok: result.ok }
    },
    [commands, devices],
  )

  const openInApp = useCallback(async (id: string) => {
    // Through storage rather than an event: the main window's page is alive
    // even when hidden, but a storage write is what it is already listening to
    // for the layout, and it survives the window being brought forward first.
    globalThis.localStorage.setItem(OPEN_FEATURE_KEY, `${String(Date.now())}:${id}`)
    await showMainWindow()
  }, [])

  return { features, devices, commands, layout, runCommand, openInApp }
}

/** A rejection with nowhere useful to go: the panel shows what it has. */
const ignore = () => {}
