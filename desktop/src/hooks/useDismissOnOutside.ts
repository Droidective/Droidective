import { useEffect, type RefObject } from "react"

/**
 * Closes a dropdown on a click outside it, or on Escape.
 *
 * A webview has no menu of its own, so every dropdown here is a positioned div
 * that has to dismiss itself. The listeners are registered unconditionally
 * rather than only while open: the effect then has one shape and one cleanup,
 * and a closed menu ignores both events instead of resubscribing on every
 * toggle.
 */
export function useDismissOnOutside(
  container: RefObject<HTMLElement | null>,
  close: (open: false) => void,
): void {
  useEffect(() => {
    const onMouseDown = (event: MouseEvent) => {
      if (container.current?.contains(event.target as Node) === true) return
      close(false)
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") close(false)
    }
    globalThis.addEventListener("mousedown", onMouseDown)
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("mousedown", onMouseDown)
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [container, close])
}
