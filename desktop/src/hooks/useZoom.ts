import { useEffect } from "react"
import { zoomScale } from "@/lib/zoom"

/**
 * Applies ⌘= / ⌘- zoom to the whole window.
 *
 * The content is laid out at `size / scale` and then scaled up — which is
 * exactly what the Mac's comment says its `scaleEffect` does, and it means the
 * layout *reflows* at the new size rather than being magnified.
 *
 * The sizing is explicit rather than left to the engine. `zoom` on the root
 * element behaves like browser page zoom only where the standardised version
 * shipped (Chromium 128+, so WebView2); WebKit's older `zoom` does not
 * necessarily rescale the initial containing block, and this app also runs on
 * WebKitGTK. Setting the zoomed element to `100% / scale` lands on the right
 * size under either reading, so there is nothing to be wrong about.
 *
 * At 1× everything is cleared, as the Mac bypasses its transform entirely
 * there: a scaled coordinate space is a thing to be out of when nothing asked
 * for it.
 */
export function useZoom(step: number): void {
  useEffect(() => {
    const root = globalThis.document.querySelector<HTMLElement>("#root")
    if (root === null) return
    const scale = zoomScale(step)
    if (scale === 1) {
      root.style.removeProperty("zoom")
      root.style.removeProperty("width")
      root.style.removeProperty("height")
      return
    }
    root.style.zoom = String(scale)
    root.style.width = `calc(100% / ${String(scale)})`
    root.style.height = `calc(100% / ${String(scale)})`
    return () => {
      root.style.removeProperty("zoom")
      root.style.removeProperty("width")
      root.style.removeProperty("height")
    }
  }, [step])
}
