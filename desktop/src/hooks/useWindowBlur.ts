import { useEffect, useMemo, useState } from "react"

import { useAppearance } from "@/hooks/useAppearance"
import { setWindowBlur, windowBlurSupported } from "@/lib/daemon-windows"
import { isTranslucent } from "@/lib/window-effects"
import { currentWindowLabel } from "@/lib/window-layout"

export interface WindowBlur {
  /** Whether this platform has a window blur to ask for at all. */
  supported: boolean
  /** What the platform said when it refused, for the Settings row to relay. */
  failure: string | null
}

/**
 * Keeps the platform's window blur in step with the Appearance setting.
 *
 * The blur is applied to the *native* window rather than in the page: what is
 * behind a window is not something a webview can reach, and `backdrop-filter`
 * only blurs what is behind an element within the same page.
 *
 * It is asked for only while the window is actually translucent. Acrylic over
 * an opaque window is invisible and costs compositing on every resize, which is
 * the one thing Tauri's own documentation warns about.
 */
export function useWindowBlur(): WindowBlur {
  const { blur, opacity } = useAppearance()
  const [supported, setSupported] = useState(false)
  const [failure, setFailure] = useState<string | null>(null)

  useEffect(() => {
    let live = true
    void windowBlurSupported()
      .then((answer) => {
        if (live) setSupported(answer)
      })
      .catch(() => {
        // An older daemon shell without the command. Reporting it as
        // unsupported is exactly right.
        if (live) setSupported(false)
      })
    return () => {
      live = false
    }
  }, [])

  const label = useMemo(() => currentWindowLabel(globalThis.location.search), [])
  const wanted = blur && isTranslucent(opacity)
  useEffect(() => {
    if (!supported) return
    let live = true
    void setWindowBlur(label, wanted)
      .then(() => {
        if (live) setFailure(null)
      })
      .catch((thrown: unknown) => {
        if (live) setFailure(thrown instanceof Error ? thrown.message : String(thrown))
      })
    return () => {
      live = false
    }
  }, [supported, wanted, label])

  return { supported, failure }
}
