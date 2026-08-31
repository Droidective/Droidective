import { useEffect } from "react"
import {
  Check,
  ChevronDown,
  Layers,
  Link2,
  PlayCircle,
  Smartphone,
  Wifi,
} from "lucide-react"
import { WindowsGroup } from "@/components/DeviceMenuWindows"
import { cn } from "@/lib/cn"
import type { Avd, Device } from "@/lib/wire"

/**
 * The device dropdown — the Mac's `deviceControl` menu.
 *
 * Its sections, in its order: the devices, the AVDs that are not already
 * running, the two wireless-debugging entries, then Manage emulators. A native
 * `<select>` cannot hold sections that *do* things, which is why this is a
 * popover: the Mac's menu is where an emulator gets launched and a device gets
 * paired, and losing that would mean losing the shortest path to both.
 */
export function DeviceMenu({
  devices,
  selected,
  avds,
  disabled,
  onSelect,
  onLaunchAvd,
  onPair,
  onConnect,
  onManageEmulators,
  onDismiss,
}: {
  devices: Device[]
  selected: Device | null
  avds: Avd[]
  /** True while run-on-all is in effect, as the Mac disables its pill. */
  disabled: boolean
  onSelect: (serial: string) => void
  onLaunchAvd: (avd: Avd) => void
  onPair: () => void
  onConnect: () => void
  onManageEmulators: () => void
  onDismiss: () => void
}) {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDismiss])

  // Launchable only: an AVD already running is in the device list above, and
  // launching it again is not a thing to offer.
  const launchable = avds.filter((avd) => avd.runningSerial === null)

  const act = (run: () => void) => () => {
    run()
    onDismiss()
  }

  return (
    <>
      <div
        className="fixed inset-0 z-40"
        onPointerDown={onDismiss}
        onContextMenu={(event) => {
          event.preventDefault()
          onDismiss()
        }}
      />
      <div
        role="menu"
        className={cn(
          "absolute left-0 top-[calc(100%+4px)] z-50 max-h-[70vh] w-[292px] overflow-y-auto",
          "rounded-lg border border-border-subtle bg-bg-raised py-1 shadow-xl",
        )}
      >
        <Devices devices={devices} selected={selected} disabled={disabled} onSelect={onSelect} />

        {launchable.length === 0 ? null : (
          <Group title="Start an emulator">
            {launchable.map((avd) => (
              <Item
                key={avd.name}
                icon={<PlayCircle size={13} />}
                onSelect={act(() => {
                  onLaunchAvd(avd)
                })}
              >
                {avd.displayName}
              </Item>
            ))}
          </Group>
        )}

        <WindowsGroup onDismiss={onDismiss} serial={selected?.serial ?? null} />

        <Group title="Wireless debugging">
          <Item icon={<Link2 size={13} />} onSelect={act(onPair)}>
            Pair new device…
          </Item>
          <Item icon={<Wifi size={13} />} onSelect={act(onConnect)}>
            Connect to device…
          </Item>
        </Group>

        <div className="my-1 h-px bg-border-subtle" />
        <Item icon={<Layers size={13} />} onSelect={act(onManageEmulators)}>
          Manage emulators…
        </Item>
      </div>
    </>
  )
}

function Devices({
  devices,
  selected,
  disabled,
  onSelect,
}: {
  devices: Device[]
  selected: Device | null
  disabled: boolean
  onSelect: (serial: string) => void
}) {
  if (devices.length === 0) {
    return <p className="px-3 py-1.5 text-[12.5px] text-text-tertiary">No devices connected</p>
  }
  return (
    <>
      {devices.map((device) => (
        <Item
          key={device.serial}
          disabled={disabled}
          onSelect={() => {
            onSelect(device.serial)
          }}
          icon={
            device.serial === selected?.serial ? (
              <Check size={13} />
            ) : device.isWireless ? (
              <Wifi size={13} />
            ) : (
              <Smartphone size={13} />
            )
          }
        >
          {device.state === "device" ? device.label : `${device.label} — ${device.state}`}
        </Item>
      ))}
    </>
  )
}

/** A titled run of items, the way an NSMenu `Section` reads. */
export function Group({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <>
      <div className="my-1 h-px bg-border-subtle" />
      <h3 className="px-3 pb-0.5 pt-1 text-[10.5px] uppercase tracking-[0.06em] text-text-tertiary">
        {title}
      </h3>
      {children}
    </>
  )
}

export function Item({
  icon,
  disabled = false,
  onSelect,
  children,
}: {
  icon: React.ReactNode
  disabled?: boolean
  onSelect: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      onClick={onSelect}
      className={cn(
        "flex w-full items-center gap-2 px-3 py-1 text-left text-[12.5px]",
        disabled ? "cursor-not-allowed text-text-tertiary" : "text-text-primary hover:bg-accent/20",
      )}
    >
      <span className="w-[13px] shrink-0 text-text-tertiary">{icon}</span>
      <span className="min-w-0 flex-1 truncate">{children}</span>
    </button>
  )
}

/** The pill the menu hangs off, matching the Mac's device pill. */
export function DevicePill({
  device,
  open,
  disabled,
  onToggle,
}: {
  device: Device | null
  open: boolean
  disabled: boolean
  onToggle: () => void
}) {
  return (
    <button
      type="button"
      aria-haspopup="menu"
      aria-expanded={open}
      disabled={disabled}
      title={disabled ? "Turn off Run on all to change the device" : "Switch the active device"}
      onClick={onToggle}
      className={cn(
        "flex max-w-[220px] items-center gap-2 rounded-[7px] border px-2.5 py-1",
        "border-text-primary/[0.18] bg-text-primary/[0.06] text-[13px] font-semibold",
        "text-text-primary disabled:cursor-not-allowed disabled:opacity-50",
        disabled ? "" : "hover:bg-text-primary/[0.1]",
      )}
    >
      <span className="min-w-0 truncate">{device?.label ?? "No device connected"}</span>
      <ChevronDown size={13} className="shrink-0 text-text-secondary" />
    </button>
  )
}

/** A bare glyph button — the bar's refresh and disconnect. */
export function IconButton({
  label,
  tone = "default",
  spinning = false,
  onClick,
  children,
}: {
  label: string
  tone?: "default" | "danger"
  spinning?: boolean
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      className={cn(
        "shrink-0 rounded p-1",
        tone === "danger"
          ? "text-danger hover:bg-danger/15"
          : "text-text-tertiary hover:bg-white/[0.06] hover:text-text-primary",
        spinning ? "animate-spin" : "",
      )}
    >
      {children}
    </button>
  )
}
