import { useCallback, useEffect, useState } from "react"
import { Copy, RefreshCw } from "lucide-react"
import { Banner, Button, TextInput } from "@/components/Controls"
import { HubColumn, HubSection, IconButton } from "@/components/Hub"
import { PrivateDnsSection } from "@/components/PrivateDnsSection"
import { WirelessAdbSection } from "@/components/WirelessAdbSection"
import { useHubAction, type HubActions } from "@/hooks/useHubAction"
import { asDaemonError, wifi } from "@/lib/daemon"
import type { DaemonError, Device, WifiStatus } from "@/lib/wire"

/**
 * The Connection hub — the Mac's `NetworkConnectionView`, section for section:
 * the device's current Wi-Fi network and IP, reversing a port, the wireless ADB
 * pairing flow, and Private DNS on one scrollable screen.
 *
 * The last two are the very same sections their standalone screens show, as on
 * the Mac — `WirelessAdbView` and `PrivateDnsView` are each one `HubColumn`
 * around the section this embeds. Wi-Fi, Network Speed and Emulators stay their
 * own screens.
 *
 * The whole screen works with nothing connected: pairing a device is what you
 * do when nothing is attached, so the sections that need a device say so
 * individually rather than the screen refusing to draw.
 */
export function ConnectionHubPane({ device }: { device: Device | null }) {
  const actions = useHubAction(device)
  const serial = device?.serial ?? null

  return (
    <HubColumn>
      <ThisDeviceSection serial={serial} actions={actions} />
      <ReversePortSection serial={serial} actions={actions} />
      <WirelessAdbSection />
      {serial === null ? null : <PrivateDnsSection serial={serial} />}
    </HubColumn>
  )
}

/**
 * The device's live network context.
 *
 * Shown up front rather than behind a blind Copy, because pairing and wireless
 * connect below both need this IP — the Mac's reason, in its words.
 */
function ThisDeviceSection({ serial, actions }: { serial: string | null; actions: HubActions }) {
  const [status, setStatus] = useState<WifiStatus | null>(null)
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)

  const load = useCallback(async () => {
    setStatus(null)
    setLoaded(false)
    setError(null)
    if (serial === null) return
    try {
      const answer = await wifi(serial)
      setStatus(answer.status)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    } finally {
      setLoaded(true)
    }
  }, [serial])

  useEffect(() => {
    void load()
  }, [load])

  return (
    <>
      {error === null ? null : <Banner tone="error">{error.message}</Banner>}
      <HubSection
        title="This device"
        subtitle="The Wi-Fi network and IP address — pairing below connects to this IP."
        accessory={
          <IconButton
            icon={<RefreshCw size={13} />}
            label="Refresh"
            disabled={serial === null}
            onClick={() => {
              void load()
            }}
          />
        }
      >
        <DeviceNetwork serial={serial} status={status} loaded={loaded} actions={actions} />
      </HubSection>
    </>
  )
}

function DeviceNetwork({
  serial,
  status,
  loaded,
  actions,
}: {
  serial: string | null
  status: WifiStatus | null
  loaded: boolean
  actions: HubActions
}) {
  if (serial === null) {
    return <p className="text-text-tertiary">Connect a device to see its network.</p>
  }
  if (loaded) {
    if (status !== null && status.ipAddress !== null && status.ipAddress !== "") {
      return (
        <div className="flex items-center gap-3">
          <div className="min-w-0">
            {status.ssid === null ? null : (
              <p className="text-[11.5px] text-text-tertiary">{status.ssid}</p>
            )}
            <p className="text-[17px] font-semibold text-text-primary" data-selectable>
              {status.ipAddress}
            </p>
          </div>
          <div className="ml-auto">
            <Button
              disabled={actions.runningId === "get-ip"}
              onClick={() => {
                actions.run("get-ip")
              }}
            >
              <span className="flex items-center gap-1.5">
                <Copy size={12} />
                Copy IP
              </span>
            </Button>
          </div>
        </div>
      )
    }
    return (
      <p className="text-text-tertiary">
        No Wi-Fi connection — wireless debugging and pairing need the device on Wi-Fi.
      </p>
    )
  }
  return <p className="text-text-tertiary">Reading the device…</p>
}

function ReversePortSection({
  serial,
  actions,
}: {
  serial: string | null
  actions: HubActions
}) {
  const [port, setPort] = useState("8081")

  return (
    <HubSection
      title="Reverse a port"
      subtitle="adb reverse tunnels a device port to this machine — e.g. Metro on 8081."
    >
      <div className="flex items-center gap-2.5">
        <div className="w-[120px]">
          <TextInput value={port} onChange={setPort} placeholder="8081" ariaLabel="Port to reverse" />
        </div>
        <Button
          tone="primary"
          disabled={serial === null || actions.runningId === "reverse-port" || port.trim() === ""}
          onClick={() => {
            actions.run("reverse-port", { port: port.trim() })
          }}
        >
          Forward
        </Button>
      </div>
    </HubSection>
  )
}
