import { useEffect } from "react"
import { isMenuOwned } from "@/lib/menuKeys"
import { hasModifier } from "@/lib/platform"

export interface ShellShortcuts {
  activeTab: string | null
  onClose: (id: string) => void
  onActivateIndex: (index: number) => void
  onSplit: (id: string) => void
  onPalette: () => void
  onSettings: () => void
  onToggleSidebar: () => void
  /** +1 zooms in, -1 out, 0 back to Actual Size. */
  onZoom: (direction: -1 | 0 | 1) => void
}

/**
 * The window's own keys: the tab strip, the palette, Settings, the sidebar and
 * the zoom.
 *
 * These run *before* the per-feature hotkeys and mark themselves handled, so a
 * feature can never shadow one — and `hotkeys.ts`' `reservedCommand` lists every
 * combination claimed here so the recorder refuses it by name. The two have to
 * stay in agreement; adding a key here means adding it there.
 *
 * What is left after `isMenuOwned` has taken its share: the palette's Ctrl+K,
 * the pane split's Ctrl+\, Ctrl+1–9 for the tabs, and Ctrl+0 for Actual Size.
 * Everything else with a menu item is bound by the menu — see `menuKeys.ts` for
 * why that is the right way round.
 */
export function useShellShortcuts({
  activeTab,
  onClose,
  onActivateIndex,
  onSplit,
  onPalette,
  onSettings,
  onToggleSidebar,
  onZoom,
}: ShellShortcuts): void {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // The native menu binds some of these and gets them first. Answering one
      // here too would run it twice — Ctrl+W closing two tabs — so the menu's
      // are refused outright rather than relying on the platform to consume
      // them. `menuKeys.test.ts` keeps the two lists in agreement.
      if (isMenuOwned(event)) return
      if (!hasModifier(event) || event.altKey) return
      // Zoom first: ⌘0 has to be read as Actual Size rather than falling into
      // the ⌘1–⌘9 tab branch below, which would treat it as tab −1.
      const zoom = zoomDirection(event.key)
      if (zoom !== null) {
        event.preventDefault()
        onZoom(zoom)
        return
      }
      if (event.key === "k" || event.key === "t") {
        event.preventDefault()
        onPalette()
        return
      }
      // The platform's own Settings key, which the sidebar footer's tooltip has
      // been promising: SwiftUI gives the Mac ⌘, for free from its Settings
      // scene, and a webview has to bind it.
      if (event.key === ",") {
        event.preventDefault()
        onSettings()
        return
      }
      if (event.key === "b") {
        event.preventDefault()
        onToggleSidebar()
        return
      }
      if (event.key === "w") {
        event.preventDefault()
        if (activeTab !== null) onClose(activeTab)
        return
      }
      // Backslash, not D. Ctrl+D is end-of-input in every Linux shell, and a
      // Terminal feature is on the way; this is the split editor binding
      // people already have in their fingers from VS Code, and it is the same
      // physical key on all three platforms.
      if (event.key === "\\") {
        event.preventDefault()
        if (activeTab !== null) onSplit(activeTab)
        return
      }
      // ⌘1–⌘9 / Ctrl+1–9. Read as a single character rather than parsed, so a
      // keyboard that sends "10" or "١" cannot land on an unintended tab.
      if (event.key < "1" || event.key > "9" || event.key.length !== 1) return
      event.preventDefault()
      onActivateIndex(Number(event.key) - 1)
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [activeTab, onClose, onActivateIndex, onSplit, onPalette, onSettings, onToggleSidebar, onZoom])
}

/**
 * Which way a zoom key goes, or null when it is not one.
 *
 * "+" and "_" are the shifted forms of the same physical keys, which is what
 * makes ⇧⌘+ work as zoom in — the shape every browser has trained people on.
 */
function zoomDirection(key: string): -1 | 0 | 1 | null {
  if (key === "=" || key === "+") return 1
  if (key === "-" || key === "_") return -1
  if (key === "0") return 0
  return null
}
