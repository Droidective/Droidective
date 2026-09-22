import { useCallback, useEffect, useState } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import { activeOverrides, asDaemonError, resetOverrides } from "@/lib/daemon"
import type { ActiveOverride } from "@/lib/wire"

/**
 * What this device currently has overridden, and clearing it.
 *
 * Reconciled against the device rather than read from a record — the daemon's
 * `OverridesService` reads back the kinds it can (proxy, layout, animation,
 * dark mode) and trusts the record only for the ones a device cannot be asked
 * about. That is what makes "Reset all overrides" honest enough to offer: it
 * appears only when there is something to reset.
 *
 * Re-read after a reset *and* after anything the hub applies, since applying an
 * override is what creates one.
 */
export function useActiveOverrides(serial: string | null): {
  overrides: ActiveOverride[]
  refresh: () => void
  resetAll: () => void
  busy: boolean
} {
  const { show } = useNotifications()
  const [overrides, setOverrides] = useState<ActiveOverride[]>([])
  const [busy, setBusy] = useState(false)

  const refresh = useCallback(() => {
    if (serial === null) {
      setOverrides([])
      return
    }
    activeOverrides(serial).then(
      (answer) => {
        setOverrides(answer.overrides)
      },
      () => {
        // Silent: this is a read nobody asked for, and a device that went away
        // mid-poll is already reported by everything else on the screen.
        setOverrides([])
      },
    )
  }, [serial])

  useEffect(refresh, [refresh])

  return {
    overrides,
    refresh,
    busy,
    resetAll: () => {
      if (serial === null) return
      setBusy(true)
      resetOverrides(serial)
        .then(
          (result) => {
            show({ message: result.message, ok: result.ok })
            refresh()
          },
          (thrown: unknown) => {
            show({ message: asDaemonError(thrown).message, ok: false })
          },
        )
        .finally(() => {
          setBusy(false)
        })
    },
  }
}
