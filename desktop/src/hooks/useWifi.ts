import { useCallback, useEffect, useState } from "react"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, connectWifi, copyText, setWifiEnabled, wifi } from "@/lib/daemon"
import type { DaemonError, WifiResponse } from "@/lib/wire"

/**
 * The Wi-Fi screen's state.
 *
 * Every command re-reads afterwards, as `WiFiView` does: toggling the radio or
 * joining a network changes the status, the saved list, or both, and showing
 * what was *asked for* rather than what the device now reports is how a screen
 * ends up lying about a command a ROM quietly refused.
 */
export function useWifi(serial: string | null) {
  const { show } = useNotifications()
  const [data, setData] = useState<WifiResponse | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)
  const [loaded, setLoaded] = useState(false)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    if (serial === null) return
    setError(null)
    try {
      setData(await wifi(serial))
      setLoaded(true)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [serial])

  useEffect(() => {
    setData(null)
    setLoaded(false)
    void load()
  }, [load])

  const run = useCallback(
    (command: (serial: string) => Promise<{ ok: boolean; message: string }>) => {
      if (serial === null) return
      setBusy(true)
      void (async () => {
        try {
          const result = await command(serial)
          show({ ok: result.ok, message: result.message })
        } catch (thrown) {
          show({ ok: false, message: asDaemonError(thrown).message })
        } finally {
          setBusy(false)
          await load()
        }
      })()
    },
    [load, serial, show],
  )

  return {
    data,
    error,
    loaded,
    busy,

    refresh: useCallback(() => {
      void load()
    }, [load]),

    setEnabled: useCallback(
      (on: boolean) => {
        run((device) => setWifiEnabled(device, on))
      },
      [run],
    ),

    connect: useCallback(
      (ssid: string, security: string, password: string) => {
        run((device) => connectWifi({ serial: device, ssid: ssid.trim(), security, password }))
      },
      [run],
    ),

    /**
     * Puts a saved password on the clipboard.
     *
     * Here rather than in the pane so the screen's one reporting surface stays
     * in one place — every other Wi-Fi outcome already goes through `show`.
     */
    copyPassword: useCallback(
      (password: string) => {
        copyText(password).then(
          () => {
            show({ ok: true, message: "Password copied" })
          },
          (thrown: unknown) => {
            show({ ok: false, message: asDaemonError(thrown).message })
          },
        )
      },
      [show],
    ),
  }
}
