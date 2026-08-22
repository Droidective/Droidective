import { useEffect } from "react"
import { hotkeyEffect, modifiersOf, resolveHotkey, type HotkeyBindings } from "@/lib/hotkeys"
import { IS_MAC } from "@/lib/platform"
import type { FeatureSummary } from "@/lib/wire"

/**
 * Makes a recorded shortcut do something — the Mac's `HotkeyManager.install`.
 *
 * An instant action runs where it stands; anything else opens its screen. The
 * Mac's toggles run too, flipping the override state it tracks, which this app
 * does not keep — so `hotkeyEffect` opens them rather than guessing a direction
 * and writing it to a device.
 *
 * These are window shortcuts, not OS-registered ones: they fire while
 * Droidective has focus. The global registration arrives with the Quick Actions
 * panel (backlog 19–20 in `docs/desktop-parity.md`), and the recorder says as
 * much rather than promising it now.
 */
export function useFeatureHotkeys({
  bindings,
  features,
  onRun,
  onOpen,
}: {
  bindings: HotkeyBindings
  features: readonly FeatureSummary[]
  onRun: (feature: FeatureSummary) => void
  onOpen: (id: string) => void
}): void {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // Anything already acted on — the tab strip's keys, a field's own
      // handling — is not ours to reinterpret. `resolveHotkey` refuses the
      // shell's combinations too, so this does not depend on which listener the
      // browser reached first.
      if (event.defaultPrevented) return
      const id = resolveHotkey(bindings, { ...modifiersOf(event), code: event.code }, IS_MAC)
      if (id === null) return
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
  }, [bindings, features, onRun, onOpen])
}
