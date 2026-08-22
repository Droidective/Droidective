import { useCallback, useEffect, useState } from "react"
import { useNotifications } from "@/hooks/useNotifications"
import {
  asDaemonError,
  devSettings,
  remountSystem,
  restrictions,
  writeRestriction,
} from "@/lib/daemon"
import type {
  DaemonError,
  DevSettingsResponse,
  RestrictionKey,
  RestrictionsResponse,
  RunResponse,
} from "@/lib/wire"

/**
 * Loading and writing one Developer Options table.
 *
 * The write behaviour is the Mac's, and it is deliberate: a flip lands on the
 * one row immediately, the adb round-trip happens behind it, and the table is
 * re-read **only if the device refused**. No busy flag, so the rest of the form
 * stays live during the round-trip rather than flashing disabled — which is
 * what `DeveloperSettingsView`'s comment on `applyToggle` insists on.
 *
 * The optimistic value surviving depends on every setter writing something the
 * device echoes back the same way. That holds for this table; a future row
 * whose value the device normalises differently would have to reload on
 * success too.
 */
export function useDeveloperSettings(serial: string | null) {
  const { show } = useNotifications()
  const [settings, setSettings] = useState<DevSettingsResponse | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)
  const [refreshing, setRefreshing] = useState(false)

  const load = useCallback(async () => {
    if (serial === null) return
    setError(null)
    try {
      setSettings(await devSettings(serial))
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [serial])

  useEffect(() => {
    setSettings(null)
    void load()
  }, [load])

  const refresh = useCallback(() => {
    setRefreshing(true)
    void load().finally(() => {
      setRefreshing(false)
    })
  }, [load])

  /** Flip a row now; reconcile with the device only if it says no. */
  const apply = useCallback(
    (optimistic: (current: DevSettingsResponse) => DevSettingsResponse, write: () => Promise<RunResponse>) => {
      setSettings((current) => (current === null ? current : optimistic(current)))
      void (async () => {
        try {
          const result = await write()
          if (!result.ok) {
            show({ ok: false, message: result.message })
            await load()
          }
        } catch (thrown) {
          show({ ok: false, message: asDaemonError(thrown).message })
          await load()
        }
      })()
    },
    [load, show],
  )

  return { settings, error, refreshing, refresh, apply }
}

/** The same table with one toggle flipped. */
export function withToggle(
  settings: DevSettingsResponse,
  id: string,
  on: boolean,
): DevSettingsResponse {
  return {
    ...settings,
    toggles: settings.toggles.map((toggle) => (toggle.id === id ? { ...toggle, on } : toggle)),
  }
}

/** The same table with one scale set. */
export function withScale(
  settings: DevSettingsResponse,
  id: string,
  value: number,
): DevSettingsResponse {
  return {
    ...settings,
    scales: settings.scales.map((scale) => (scale.id === id ? { ...scale, value } : scale)),
  }
}

/**
 * Loading and writing the dev-time restrictions.
 *
 * Same shape and same reasoning as `useDeveloperSettings` — optimistic toggle,
 * reload only on refusal — with one difference the Mac also makes: remounting
 * the system partition is an explicit *action*, not a toggle, so it takes the
 * busy spinner while a toggle deliberately does not.
 */
export function useRestrictions(serial: string | null) {
  const { show } = useNotifications()
  const [state, setState] = useState<RestrictionsResponse | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    if (serial === null) return
    setError(null)
    try {
      setState(await restrictions(serial))
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [serial])

  useEffect(() => {
    setState(null)
    void load()
  }, [load])

  const reconcile = useCallback(
    async (write: () => Promise<RunResponse>) => {
      try {
        const result = await write()
        if (!result.ok) {
          show({ ok: false, message: result.message })
          await load()
        }
      } catch (thrown) {
        show({ ok: false, message: asDaemonError(thrown).message })
        await load()
      }
    },
    [load, show],
  )

  return {
    state,
    error,
    busy,

    refresh: useCallback(() => {
      setBusy(true)
      void load().finally(() => {
        setBusy(false)
      })
    }, [load]),

    toggle: useCallback(
      (key: RestrictionKey, on: boolean) => {
        if (serial === null) return
        setState((current) => (current === null ? current : { ...current, [key]: on }))
        void reconcile(() => writeRestriction({ serial, key, on }))
      },
      [reconcile, serial],
    ),

    remount: useCallback(() => {
      if (serial === null) return
      setBusy(true)
      void (async () => {
        try {
          const result = await remountSystem(serial)
          show({ ok: result.ok, message: result.message })
        } catch (thrown) {
          show({ ok: false, message: asDaemonError(thrown).message })
        } finally {
          setBusy(false)
        }
      })()
    }, [serial, show]),
  }
}
