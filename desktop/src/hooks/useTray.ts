import { useEffect } from "react"
import { listen } from "@tauri-apps/api/event"
import { setTrayMenu, showMainWindow, quitApp } from "@/lib/daemon"
import { stopAllStreams } from "@/lib/daemon-stream"
import { hotkeyEffect } from "@/lib/hotkeys"
import {
  featureOfTrayCommand,
  trayFeatures,
  trayMenu,
  TRAY_MIRROR,
  TRAY_OPEN,
  TRAY_QUIT,
  TRAY_SCREENSHOT,
} from "@/lib/tray"
import type { Device, FeatureSummary } from "@/lib/wire"

/** Rust's two events: a tray row was clicked, and the window was hidden. */
const TRAY_EVENT = "tray://command"
const BACKGROUND_EVENT = "app://background"

/**
 * The tray icon, and what happens when the window hides behind it.
 *
 * Two halves of one thing, which is why they are one hook: background mode is
 * only usable because the tray brings the window back, and the tray is only
 * worth having because the window can go away.
 *
 * The menu is pushed rather than pulled. Everything in it — the device's name,
 * the features the user chose — lives here, so the alternative would be Rust
 * asking the page for a menu at the moment of a click, which is a round trip
 * inside a click handler for data that changes about twice an hour.
 */
export function useTray({
  device,
  features,
  chosen,
  favorites,
  disabled,
  onRun,
  onOpen,
}: {
  device: Device | null
  features: readonly FeatureSummary[]
  chosen: readonly string[]
  favorites: readonly string[]
  disabled: readonly string[]
  onRun: (feature: FeatureSummary) => void
  onOpen: (id: string) => void
}): void {
  const listed = trayFeatures(features, { chosen, favorites, disabled })
  // Not the array: it is rebuilt on every render, and a menu rebuilt on every
  // render is an IPC call on every render.
  const signature = `${device?.label ?? ""}|${listed.map((feature) => feature.id).join(",")}`

  useEffect(() => {
    void setTrayMenu(
      trayMenu({ deviceLabel: device?.label ?? null, features: listed }),
    ).catch(() => {
      // A desktop with no tray. Settings already says background mode is
      // unavailable there; a toast for something nobody asked for would not.
    })
    // `listed` and `device` are what `signature` is made of — depending on them
    // directly would rebuild the menu on every render, which is the thing this
    // exists to avoid.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [signature])

  useEffect(() => {
    const pending = listen<string>(TRAY_EVENT, (event) => {
      const id = event.payload
      const featureID = featureOfTrayCommand(id)
      if (featureID !== null) {
        const feature = features.find((candidate) => candidate.id === featureID)
        if (feature === undefined) return
        // An instant action runs where it stands, with no window — which is
        // the whole point of the menu-bar extra on the Mac. Anything else
        // needs the window back first.
        if (hotkeyEffect(feature.kind) === "run") {
          onRun(feature)
          return
        }
        void showMainWindow()
        onOpen(feature.id)
        return
      }
      if (id === TRAY_SCREENSHOT) {
        const screenshot = features.find((feature) => feature.id === "screenshot")
        if (screenshot !== undefined) onRun(screenshot)
      } else if (id === TRAY_MIRROR) {
        void showMainWindow()
        onOpen("scrcpy")
      } else if (id === TRAY_OPEN) {
        void showMainWindow()
      } else if (id === TRAY_QUIT) {
        void quitApp()
      }
    })
    return () => {
      void pending.then((unlisten) => {
        unlisten()
      })
    }
  }, [features, onRun, onOpen])

  useEffect(() => {
    const pending = listen(BACKGROUND_EVENT, () => {
      // `AppState.enterBackground`: stop the work that was only running
      // because a window was open. Nothing here is resumed on the way back —
      // the Mac does not resume it either, and a screen re-entered subscribes
      // again the way it did the first time.
      void stopAllStreams()
    })
    return () => {
      void pending.then((unlisten) => {
        unlisten()
      })
    }
  }, [])
}
