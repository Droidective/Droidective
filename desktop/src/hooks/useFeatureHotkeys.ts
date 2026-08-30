import { useEffect, useState } from "react"
import { listen } from "@tauri-apps/api/event"
import { accelerator } from "@/lib/accelerator"
import { setGlobalShortcuts, showMainWindow, toggleQuickPanel } from "@/lib/daemon"
import {
  hotkeyEffect,
  modifiersOf,
  resolveHotkey,
  type Hotkey,
  type HotkeyBindings,
} from "@/lib/hotkeys"
import { IS_MAC } from "@/lib/platform"
import type { FeatureSummary } from "@/lib/wire"

/** Rust's event, carrying the accelerator in the platform's own spelling. */
const SHORTCUT_EVENT = "shortcut://pressed"

/** The panel's registration id. Not a feature, and no registry id looks like it. */
const PANEL_ID = "quick-actions-panel"

/**
 * Makes a recorded shortcut do something — the Mac's `HotkeyManager.install`.
 *
 * An instant action runs where it stands; anything else opens its screen. The
 * Mac's toggles run too, flipping the override state it tracks, which this app
 * does not keep — so `hotkeyEffect` opens them rather than guessing a direction
 * and writing it to a device.
 *
 * **Two registrations, and the split is not belt and braces.** Each binding is
 * offered to the OS, which is what makes a shortcut worth recording: it then
 * fires from whatever app you are in, and from a window closed into the tray.
 * But the platform refuses a combination another app already holds, and a
 * shortcut that consequently worked *nowhere* would be worse than one that
 * works while Droidective has focus — so the window listener goes on answering
 * for exactly the ones that did not register. Nothing is answered twice: a
 * registered shortcut is grabbed, and the keystroke never reaches the webview.
 */
export function useFeatureHotkeys({
  bindings,
  panelHotkey,
  features,
  onRun,
  onOpen,
}: {
  bindings: HotkeyBindings
  /** Settings ▸ Hotkeys ▸ Global ▸ Quick Actions panel, or null. */
  panelHotkey: Hotkey | null
  features: readonly FeatureSummary[]
  onRun: (feature: FeatureSummary) => void
  onOpen: (id: string) => void
}): void {
  const global = useGlobalRegistration({ bindings, panelHotkey, features, onRun, onOpen })

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // Anything already acted on — the tab strip's keys, a field's own
      // handling — is not ours to reinterpret. `resolveHotkey` refuses the
      // shell's combinations too, so this does not depend on which listener the
      // browser reached first.
      if (event.defaultPrevented) return
      const id = resolveHotkey(bindings, { ...modifiersOf(event), code: event.code }, IS_MAC)
      if (id === null || global.has(id)) return
      const feature = features.find((candidate) => candidate.id === id)
      if (feature === undefined) return
      event.preventDefault()
      if (hotkeyEffect(feature.kind) === "run") onRun(feature)
      else onOpen(feature.id)
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [bindings, features, global, onRun, onOpen])
}

/**
 * The OS half: registers the bindings and answers presses.
 *
 * Returns the feature ids the platform accepted, which is what tells the window
 * listener above to stand down for them.
 */
function useGlobalRegistration({
  bindings,
  panelHotkey,
  features,
  onRun,
  onOpen,
}: {
  bindings: HotkeyBindings
  panelHotkey: Hotkey | null
  features: readonly FeatureSummary[]
  onRun: (feature: FeatureSummary) => void
  onOpen: (id: string) => void
}): ReadonlySet<string> {
  /** Canonical accelerator → feature id, for the presses that arrive. */
  const [registered, setRegistered] = useState<ReadonlyMap<string, string>>(new Map())

  // A stable description of the bindings, so registration happens when they
  // change rather than on every render.
  const signature = Object.entries(bindings)
    .map(([id, hotkey]) => `${id}:${accelerator(hotkey)}`)
    .toSorted()
    .join("|")
    .concat(panelHotkey === null ? "" : `|${PANEL_ID}:${accelerator(panelHotkey)}`)

  useEffect(() => {
    let live = true
    const wanted = Object.entries(bindings).map(([id, hotkey]) => ({
      id,
      requested: accelerator(hotkey),
    }))
    // The panel rides the same registration. It is not a feature, so it gets
    // an id no registry entry can collide with, and the press handler below
    // recognises it before it looks anything up.
    if (panelHotkey !== null) {
      wanted.push({ id: PANEL_ID, requested: accelerator(panelHotkey) })
    }
    void setGlobalShortcuts(wanted.map((entry) => entry.requested)).then(
      (accepted) => {
        if (!live) return
        const table = new Map<string, string>()
        for (const entry of accepted) {
          const owner = wanted.find((candidate) => candidate.requested === entry.requested)
          if (owner !== undefined) table.set(entry.canonical, owner.id)
        }
        setRegistered(table)
      },
      () => {
        // Outside a Tauri webview, or a platform that registered none of them.
        // The window listener then covers everything, which is where this app
        // was before.
        if (live) setRegistered(new Map())
      },
    )
    return () => {
      live = false
    }
    // `bindings` is what `signature` is made of; depending on the object itself
    // would re-register on every render.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [signature])

  useEffect(() => {
    const pending = listen<string>(SHORTCUT_EVENT, (event) => {
      const id = registered.get(event.payload)
      if (id === undefined) return
      if (id === PANEL_ID) {
        void toggleQuickPanel()
        return
      }
      const feature = features.find((candidate) => candidate.id === id)
      if (feature === undefined) return
      // The same two outcomes, plus the one thing a global shortcut needs that
      // a window one never did: a screen has to have a window to open into.
      if (hotkeyEffect(feature.kind) === "run") {
        onRun(feature)
        return
      }
      void showMainWindow()
      onOpen(feature.id)
    })
    return () => {
      void pending.then((unlisten) => {
        unlisten()
      })
    }
  }, [registered, features, onRun, onOpen])

  return new Set(registered.values())
}
