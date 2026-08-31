import { Apple, Smartphone } from "lucide-react"

import { useWindows } from "@/hooks/useWindows"
import { cn } from "@/lib/cn"
import type { Device } from "@/lib/wire"
import { windowTitle } from "@/lib/workspaces"

/**
 * The leading status icon: the colour and the tooltip live here, outside the
 * menu, exactly as the Mac splits them.
 */
export function StatusIcon({ device }: { device: Device | null }) {
  const simulator = device?.platform === "ios-simulator"
  const windows = useWindows()
  // Only the windows *after* the first are tinted, so one window looks exactly
  // as it always did and a second one is visibly a second one — `DeviceTint`
  // on the Mac. A trouble state keeps its own semaphore colour: which window
  // this is matters less than a device you cannot reach.
  const tinted = windows.tint !== null && device?.state === "device"

  return (
    <span
      className={cn("shrink-0", tinted ? "" : tone(device))}
      style={tinted ? { color: windows.tint ?? undefined } : undefined}
      title={tinted ? `${help(device)} · ${windowTitle(windows.ordinal)}` : help(device)}
    >
      {simulator ? <Apple size={14} /> : <Smartphone size={14} />}
    </span>
  )
}

function tone(device: Device | null): string {
  if (device === null) return "text-text-tertiary"
  if (device.state === "device") return "text-accent"
  // Trouble states keep their semaphore colours: unauthorised is something to
  // go and tap on the device, anything else is a fault.
  return device.state === "unauthorized" ? "text-warn" : "text-danger"
}

function help(device: Device | null): string {
  if (device === null) return "No device connected"
  if (device.state === "device") return `${device.label} — connected`
  if (device.state === "unauthorized") return `${device.label} — accept the prompt on the device`
  return `${device.label} — ${device.state}`
}
