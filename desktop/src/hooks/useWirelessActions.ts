import { useState } from "react"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, connectWireless, enableTcpip, pairWireless } from "@/lib/daemon"
import { hostPrefix } from "@/lib/endpoint"

export interface Status {
  ok: boolean
  message: string
}

export interface WirelessActions {
  /** The pairing tab's three fields. */
  pairEndpoint: string
  pairCode: string
  connectAfterPair: string
  paired: boolean
  /** The connect tab's field. */
  endpoint: string
  busy: boolean
  status: Status | null
  setPairEndpoint: (value: string) => void
  setPairCode: (value: string) => void
  setConnectAfterPair: (value: string) => void
  setEndpoint: (value: string) => void
  clearStatus: () => void
  pair: () => void
  connect: (endpoint: string) => void
  switchToWifi: (serial: string) => void
}

/**
 * The wireless sheet's four calls and everything they type into.
 *
 * A hook rather than state in the sheet because the sheet is three tabs over
 * one flow: the pairing tab writes the connect field, and every tab shares one
 * busy flag and one status line. Kept together, that is a small state machine;
 * spread across the tabs it would be three copies of it.
 */
export function useWirelessActions({
  onSelectDevice,
  onDismiss,
}: {
  onSelectDevice: (serial: string) => void
  onDismiss: () => void
}): WirelessActions {
  const { attempt, finish, busy, status, clearStatus } = useAttempt({ onSelectDevice, onDismiss })
  const [pairEndpoint, setPairEndpoint] = useState("")
  const [pairCode, setPairCode] = useState("")
  const [connectAfterPair, setConnectAfterPair] = useState("")
  const [paired, setPaired] = useState(false)
  const [endpoint, setEndpoint] = useState("")

  const connect = (text: string) => {
    attempt(async () => {
      const result = await connectWireless(text)
      if (result.ok) finish(result.message, text.trim())
      return { ok: result.ok, message: result.message }
    })
  }

  /**
   * Pair, then finish the job when the device says where to reach it.
   *
   * A paired device advertises its connect port over mDNS, and the daemon looks
   * it up as part of answering — so on success there is usually nothing left to
   * type. When there is not (older adb, mDNS off, a different subnet), the
   * connect field is prefilled with "ip:" so only the port from the Wireless
   * debugging screen is missing.
   */
  const pair = () => {
    attempt(async () => {
      const { result, discovered } = await pairWireless(pairEndpoint, pairCode)
      if (!result.ok) return { ok: false, message: result.message }
      setPaired(true)
      if (discovered === null) {
        setConnectAfterPair(`${hostPrefix(pairEndpoint)}:`)
        return {
          ok: true,
          message: "Paired — enter the port from the Wireless debugging screen to connect.",
        }
      }
      const address = `${discovered.host}:${discovered.port}`
      setConnectAfterPair(address)
      const connected = await connectWireless(address)
      if (connected.ok) finish(connected.message, address)
      return { ok: connected.ok, message: connected.message }
    })
  }

  const switchToWifi = (serial: string) => {
    attempt(async () => {
      const result = await enableTcpip(serial)
      // tcpip can succeed without the auto-connect, when the device's IP could
      // not be read. Only a real connection closes the sheet.
      if (result.ok && result.copyText !== null && result.message.startsWith("Connected")) {
        finish(result.message, result.copyText)
      }
      return { ok: result.ok, message: result.message }
    })
  }

  return {
    pairEndpoint,
    pairCode,
    connectAfterPair,
    paired,
    endpoint,
    busy,
    status,
    setPairEndpoint,
    setPairCode,
    setConnectAfterPair,
    setEndpoint,
    clearStatus,
    pair,
    connect,
    switchToWifi,
  }
}

/**
 * One call at a time, and what it said — plus what to do when a device becomes
 * reachable.
 *
 * Every tab of the sheet shares this: one busy flag, one status line, and one
 * definition of "connected" (select it, toast it, close). Its own hook so the
 * three calls above read as calls.
 */
function useAttempt({
  onSelectDevice,
  onDismiss,
}: {
  onSelectDevice: (serial: string) => void
  onDismiss: () => void
}) {
  const { show } = useNotifications()
  const [busy, setBusy] = useState(false)
  const [status, setStatus] = useState<Status | null>(null)

  return {
    busy,
    status,
    clearStatus: () => {
      setStatus(null)
    },
    attempt: (work: () => Promise<Status>) => {
      setBusy(true)
      setStatus(null)
      void (async () => {
        try {
          setStatus(await work())
        } catch (thrown) {
          setStatus({ ok: false, message: asDaemonError(thrown).message })
        } finally {
          setBusy(false)
        }
      })()
    },
    /**
     * A device is now reachable over Wi-Fi: select it, hand the confirmation to
     * a toast — it has to outlive the sheet — and close.
     */
    finish: (message: string, serial: string) => {
      onSelectDevice(serial)
      show({ message, ok: true, important: true })
      onDismiss()
    },
  }
}
