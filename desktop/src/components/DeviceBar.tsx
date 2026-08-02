import { ChevronDown, Smartphone, Wifi } from "lucide-react"
import { cn } from "@/lib/cn"
import type { Device } from "@/lib/wire"

/**
 * The persistent device strip.
 *
 * A dropdown rather than a row of chips, matching the Mac app's device
 * picker — the bar stays the same height whether one device is attached or
 * five, which is what makes it read as chrome.
 */
export function DeviceBar({
  devices,
  devicesLoaded,
  selected,
  onSelect,
}: {
  devices: Device[]
  devicesLoaded: boolean
  selected: Device | null
  onSelect: (serial: string) => void
}) {
  return (
    <div className="flex h-[46px] shrink-0 items-center gap-2 border-b border-border-subtle bg-bg-chrome px-3">
      {devices.length === 0 ? (
        <span className="pl-1 text-text-secondary">
          {devicesLoaded ? "No devices — connect one over USB or Wi-Fi" : "Looking for devices…"}
        </span>
      ) : (
        <DevicePicker devices={devices} selected={selected} onSelect={onSelect} />
      )}
    </div>
  )
}

function DevicePicker({
  devices,
  selected,
  onSelect,
}: {
  devices: Device[]
  selected: Device | null
  onSelect: (serial: string) => void
}) {
  const ready = selected?.state === "device"
  return (
    <div
      className={cn(
        "relative flex items-center gap-2 rounded-md border border-border-subtle bg-bg-raised",
        "py-1 pl-2.5 pr-2 focus-within:border-accent",
      )}
    >
      <span className={cn("shrink-0", ready ? "text-accent" : "text-warn")}>
        {selected?.isWireless ? <Wifi size={14} /> : <Smartphone size={14} />}
      </span>
      {/* A native select: it gets the platform's own menu, keyboard handling
          and overflow behaviour for free, which a hand-rolled popover on three
          platforms would not. */}
      <select
        value={selected?.serial ?? ""}
        aria-label="Device"
        onChange={(event) => {
          onSelect(event.target.value)
        }}
        className="appearance-none bg-transparent pr-4 text-[13px] text-text-primary outline-none"
      >
        {devices.map((device) => (
          <option key={device.serial} value={device.serial}>
            {device.label}
            {device.state === "device" ? "" : ` — ${device.state}`}
          </option>
        ))}
      </select>
      <ChevronDown size={13} className="pointer-events-none -ml-4 shrink-0 text-text-secondary" />
    </div>
  )
}
