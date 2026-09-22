import { useEffect, useRef, useState } from "react"

import type { Device } from "@/lib/wire"

/**
 * Announce a device dropping off, once, the way the Mac's alert does.
 *
 * It fires on the *transition* to nothing connected, not on the state: opening
 * this screen with no device is the ordinary case here — the relay is a
 * listener on this machine and runs with nothing plugged in — and an alert then
 * would be an interruption rather than news.
 *
 * Only while this tab is the one on screen. Every open tab stays mounted, so
 * without the guard a hidden Reactotron tab would put a modal over whatever
 * someone was actually looking at.
 */
export function useDisconnectAlert(
  device: Device | null,
  active: boolean,
): { showing: boolean; dismiss: () => void } {
  const [showing, setShowing] = useState(false)
  const had = useRef(device !== null)

  useEffect(() => {
    const has = device !== null
    if (had.current && !has && active) setShowing(true)
    had.current = has
  }, [device, active])

  return { showing, dismiss: () => { setShowing(false) } }
}
