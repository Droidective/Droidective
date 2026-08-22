import { useEffect, useState } from "react"
import {
  afterButtonPress,
  afterModeChange,
  afterToggle,
  pinnedSidebar,
  type SidebarMode,
} from "@/lib/sidebarMode"

export interface SidebarModeController {
  mode: SidebarMode
  /** The device bar's button: flips pinned ↔ auto-hide, or un-evicts. */
  pressButton: () => void
  /** ⌘B: peeks the auto-hiding sidebar, or hides and shows the pinned one. */
  toggle: () => void
  /** The left-edge hover, which only means anything in auto-hide mode. */
  peek: (shown: boolean) => void
}

/**
 * The live sidebar state over the persisted mode.
 *
 * Only `autoHide` is remembered between launches, as on the Mac: whether the
 * sidebar happens to be peeked or evicted right now is a fact about this
 * session. `afterModeChange` reconciles when the persisted flag changes under
 * us — Settings ▸ Appearance can flip it — so that path and the button cannot
 * drift, which is the reason ADBKit has the model at all.
 */
export function useSidebarMode(
  autoHide: boolean,
  persist: (autoHide: boolean) => void,
): SidebarModeController {
  const [mode, setMode] = useState<SidebarMode>(() => afterModeChange(pinnedSidebar(), autoHide))

  useEffect(() => {
    setMode((current) => (current.autoHide === autoHide ? current : afterModeChange(current, autoHide)))
  }, [autoHide])

  return {
    mode,
    pressButton: () => {
      // Computed outside the updater: persisting is a side effect, and an
      // updater can run twice.
      const next = afterButtonPress(mode)
      setMode(next)
      if (next.autoHide !== mode.autoHide) persist(next.autoHide)
    },
    toggle: () => {
      setMode(afterToggle)
    },
    peek: (shown: boolean) => {
      setMode((current) => (current.autoHide ? { ...current, overlayShown: shown } : current))
    },
  }
}
