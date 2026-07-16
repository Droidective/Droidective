import { useSyncExternalStore } from "react"

const query = "(hover: hover) and (pointer: fine)"

function subscribe(onChange: () => void) {
  const mql = window.matchMedia(query)
  mql.addEventListener("change", onChange)
  return () => mql.removeEventListener("change", onChange)
}

/** True on mouse/trackpad devices; false on touch devices, where the
 *  pointer-driven effects (dot field, hover states) have nothing to react to. */
export function useFinePointer(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(query).matches,
    () => false,
  )
}
