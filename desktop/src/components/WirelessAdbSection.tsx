import { useState } from "react"

import { HubSection } from "@/components/Hub"
import { useConnectedDevices } from "@/hooks/useConnectedDevices"
import { useNotifications } from "@/hooks/useNotifications"
import {
  asDaemonError,
  connectWireless,
  disconnectWireless,
  enableTcpip,
  pairWireless,
} from "@/lib/daemon"
import { cn } from "@/lib/cn"

/**
 * Wireless ADB — the Mac's `WirelessAdbSection`, section for section.
 *
 * Three of them, and the order is the order someone does this in: switch a
 * USB device over, pair a new one, then manage what is already wireless. The
 * device dropdown's sheet covers the same ground for someone who is already
 * there; this is what the feature list and the Connection hub both open.
 *
 * Nothing here takes the device bar's selection: it is about the devices
 * themselves, and is most wanted when none is selected yet.
 */
export function WirelessAdbSection() {
  const devices = useConnectedDevices()
  const { show } = useNotifications()
  const [busy, setBusy] = useState(false)

  const usb = devices.filter((device) => !device.isWireless)
  const wireless = devices.filter((device) => device.isWireless)

  /** Run one adb call, and say what it said either way. */
  const attempt = (what: string, call: () => Promise<{ ok: boolean; message: string }>) => {
    setBusy(true)
    void (async () => {
      try {
        const result = await call()
        // adb's own words, not a generic failure: "device offline" and "more
        // than one device" want different things done about them.
        show({ message: `${what}: ${result.message}`, ok: result.ok })
      } catch (thrown) {
        show({ message: `${what}: ${asDaemonError(thrown).message}`, ok: false })
      } finally {
        setBusy(false)
      }
    })()
  }

  return (
    <>
      <HubSection
        title="Wireless ADB"
        subtitle="Switch a USB-connected device to debugging over Wi-Fi."
      >
        {usb.length === 0 ? (
          <p className="text-text-tertiary">Connect a device over USB to start.</p>
        ) : (
          usb.map((device) => (
            <div key={device.serial} className="flex items-center gap-3">
              <span className="min-w-0 flex-1 truncate text-text-primary">{device.label}</span>
              <Action
                label="Enable Wi-Fi & Connect"
                busy={busy}
                onClick={() => attempt("Enable Wi-Fi & Connect", () => enableTcpip(device.serial))}
              />
            </div>
          ))
        )}
      </HubSection>

      <PairSection busy={busy} attempt={attempt} />

      {wireless.length > 0 && (
        <HubSection title="Connected over Wi-Fi">
          {wireless.map((device) => (
            <div key={device.serial} className="flex items-center gap-3">
              <span className="min-w-0 flex-1 truncate text-text-primary">{device.label}</span>
              <Action
                label="Disconnect"
                busy={busy}
                onClick={() => attempt("Disconnect", () => disconnectWireless(device.serial))}
              />
            </div>
          ))}
        </HubSection>
      )}
    </>
  )
}

function PairSection({
  busy,
  attempt,
}: {
  busy: boolean
  attempt: (what: string, call: () => Promise<{ ok: boolean; message: string }>) => void
}) {
  const [pairEndpoint, setPairEndpoint] = useState("")
  const [pairCode, setPairCode] = useState("")
  const [endpoint, setEndpoint] = useState("")

  return (
    <HubSection title="Pair a device" subtitle="Android 11+ — pair with a code, then connect.">
      <Field
        label="Pairing address"
        placeholder="192.168.1.5:37103"
        value={pairEndpoint}
        onChange={setPairEndpoint}
      />
      <Field label="Pairing code" placeholder="123456" value={pairCode} onChange={setPairCode} />
      <Action
        label="Pair"
        busy={busy || pairEndpoint.trim() === "" || pairCode.trim() === ""}
        onClick={() =>
          attempt("Pair", async () => {
            const { result } = await pairWireless(pairEndpoint.trim(), pairCode.trim())
            return result
          })
        }
      />

      <Field
        label="Connect address"
        placeholder="192.168.1.5:5555"
        value={endpoint}
        onChange={setEndpoint}
      />
      <Action
        label="Connect"
        busy={busy || endpoint.trim() === ""}
        onClick={() => attempt("Connect", () => connectWireless(endpoint.trim()))}
      />

      <p className="text-[11.5px] text-text-tertiary">
        The pairing port (from &ldquo;Pair device with pairing code&rdquo;) differs from the
        connection port shown on the device&rsquo;s Wireless debugging screen.
      </p>
    </HubSection>
  )
}

function Field({
  label,
  placeholder,
  value,
  onChange,
}: {
  label: string
  placeholder: string
  value: string
  onChange: (value: string) => void
}) {
  return (
    <label className="flex items-center gap-3">
      <span className="w-32 shrink-0 text-text-primary">{label}</span>
      <input
        type="text"
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
        className="min-w-0 flex-1 rounded border border-border-subtle bg-bg-root px-2 py-1 text-text-primary placeholder:text-text-tertiary"
      />
    </label>
  )
}

function Action({ label, busy, onClick }: { label: string; busy: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      disabled={busy}
      onClick={onClick}
      className={cn(
        "shrink-0 rounded border border-border-subtle px-2.5 py-1 text-text-primary",
        "hover:bg-bg-hover disabled:cursor-not-allowed disabled:opacity-40",
      )}
    >
      {label}
    </button>
  )
}
