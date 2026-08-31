import { useEffect, useState } from "react"

import { asDaemonError, listApps } from "@/lib/daemon"
import type { AppSummary } from "@/lib/wire"

export interface QuickBundleList {
  apps: AppSummary[]
  loading: boolean
  error: string | null
}

/**
 * The target device's installed apps, for the panel's pick-an-app step.
 *
 * User apps only, and the reason is the screen rather than the data: this list
 * is picked from with the arrow keys in a small panel, and putting three
 * hundred system packages in front of the one someone is looking for makes it
 * unusable. The Apps screen in the main window still shows everything.
 *
 * The Mac lists its saved bundles above these. There is no bundle store here
 * yet, so this is that list narrowed to what the device actually has —
 * recorded in `docs/desktop-parity.md` rather than passed off as the same.
 */
export function useQuickBundle(serial: string | null): QuickBundleList {
  const [apps, setApps] = useState<AppSummary[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (serial === null) {
      setApps([])
      return
    }
    let live = true
    setLoading(true)
    setError(null)
    void listApps(serial)
      .then((answer) => {
        if (!live) return
        setApps(answer.apps.filter((app) => !app.isSystem))
      })
      .catch((thrown: unknown) => {
        if (live) setError(asDaemonError(thrown).message)
      })
      .finally(() => {
        if (live) setLoading(false)
      })
    return () => {
      live = false
    }
  }, [serial])

  return { apps, loading, error }
}
