import { useCallback, useEffect, useState } from "react"
import { arm, CONFIRM_WINDOW_MS, isArmed, type Armed } from "@/lib/confirm"

export interface ArmedConfirm {
  /** Whether pressing this button now would actually run it. */
  isArmed: (actionId: string, target: string) => boolean
  /** Arm a button. Replaces any previous arming — only one at a time. */
  arm: (actionId: string, target: string) => void
  disarm: () => void
}

/**
 * Holds the one armed destructive action, and makes sure it goes away.
 *
 * Three things disarm it, and all three matter: pressing Cancel, the window
 * losing focus, and the window itself passing. The timer is not the guard —
 * `isArmed` is, and it re-checks the clock — but without it the button would
 * sit there reading "Really clear data?" long after the arming expired.
 */
export function useArmedConfirm(): ArmedConfirm {
  const [armed, setArmed] = useState<Armed | null>(null)

  useEffect(() => {
    if (armed === null) return
    const timer = globalThis.setTimeout(() => {
      setArmed(null)
    }, CONFIRM_WINDOW_MS)
    // Looking away is as good as saying no.
    const onBlur = () => {
      setArmed(null)
    }
    globalThis.addEventListener("blur", onBlur)
    return () => {
      globalThis.clearTimeout(timer)
      globalThis.removeEventListener("blur", onBlur)
    }
  }, [armed])

  return {
    isArmed: useCallback(
      (actionId: string, target: string) => isArmed(armed, actionId, target, Date.now()),
      [armed],
    ),
    arm: useCallback((actionId: string, target: string) => {
      setArmed(arm(actionId, target, Date.now()))
    }, []),
    disarm: useCallback(() => {
      setArmed(null)
    }, []),
  }
}
