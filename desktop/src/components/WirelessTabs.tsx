import { Cable } from "lucide-react"
import { Button } from "@/components/Controls"
import { EndpointField } from "@/components/EndpointField"
import { looksLikeEndpoint } from "@/lib/endpoint"
import type { Device } from "@/lib/wire"

/**
 * The wireless sheet's two simple tabs — connect, and the USB bootstrap.
 *
 * Beside the sheet rather than in it because the sheet is already the tab
 * switch plus the four calls behind them; the pairing tab, which has a shape of
 * its own, lives in `WirelessSteps`.
 */

/** For a device paired before, or one already switched to Wi-Fi. */
export function ConnectTab({
  endpoint,
  busy,
  onEndpoint,
  onConnect,
}: {
  endpoint: string
  busy: boolean
  onEndpoint: (value: string) => void
  onConnect: () => void
}) {
  const ready = !busy && looksLikeEndpoint(endpoint)
  return (
    <div className="flex flex-col gap-2.5">
      <p className="text-[12px] text-text-secondary">
        For a device that was paired before, or one already switched to Wi-Fi (port 5555). Find the
        address under Settings ▸ Developer options ▸ Wireless debugging.
      </p>
      <div className="flex items-end gap-3">
        <EndpointField
          label="IP address & port"
          value={endpoint}
          placeholder="192.168.1.42:5555"
          onChange={onEndpoint}
          onSubmit={ready ? onConnect : undefined}
        />
        <Button tone="primary" disabled={!ready} onClick={onConnect}>
          Connect
        </Button>
      </div>
    </div>
  )
}

/** The one-click bootstrap: a cabled device, switched over and connected. */
export function UsbTab({
  devices,
  busy,
  onSwitch,
}: {
  devices: Device[]
  busy: boolean
  onSwitch: (serial: string) => void
}) {
  // Wireless devices are already there, and one that is not ready cannot be
  // told to do anything.
  const cabled = devices.filter(
    (device) => device.platform === "android" && !device.isWireless && device.state === "device",
  )
  return (
    <div className="flex flex-col gap-2.5">
      <p className="text-[12px] text-text-secondary">
        The easiest way — plug the device in once, click below, then unplug. Droidective switches it
        to Wi-Fi debugging and connects automatically.
      </p>
      {cabled.length === 0 ? (
        <p className="flex items-center gap-2 text-[12px] text-text-tertiary">
          <Cable size={13} />
          No USB device detected — plug one in and it appears here.
        </p>
      ) : (
        cabled.map((device) => (
          <div key={device.serial} className="flex items-center gap-3">
            <span className="min-w-0 flex-1 truncate text-[13px] text-text-primary">
              {device.label}
            </span>
            <Button
              tone="primary"
              disabled={busy}
              onClick={() => {
                onSwitch(device.serial)
              }}
            >
              Switch to Wi-Fi
            </Button>
          </div>
        ))
      )}
    </div>
  )
}
