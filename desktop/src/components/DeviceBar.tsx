import { useState } from "react"
import { Layers, PanelLeft, PanelLeftDashed, RefreshCw, WifiOff } from "lucide-react"
import { AdbWarning } from "@/components/AdbWarning"
import { Switch } from "@/components/Controls"
import { DeviceMenu, DevicePill, IconButton } from "@/components/DeviceMenu"
import { NotificationBell } from "@/components/NotificationPanel"
import { WirelessSheet, type WirelessMode } from "@/components/WirelessSheet"
import { useDeviceBarActions } from "@/hooks/useDeviceBarActions"
import { StatusIcon } from "@/components/DeviceStatusIcon"
import type { Device } from "@/lib/wire"

export interface DeviceBarProps {
  devices: Device[]
  devicesLoaded: boolean
  selected: Device | null
  onSelect: (serial: string) => void
  /** Ask adb again — the button that exists for a device that never appears. */
  onRefresh: () => Promise<void>
  /** Opens a feature in the focused pane — the bar's Manage emulators entry. */
  onOpenFeature: (id: string) => void
  /** Shown only when the focused feature fans out and there is more than one device. */
  showsRunAll: boolean
  runOnAll: boolean
  onRunOnAll: (on: boolean) => void
  /** True while a fan-out is in effect, which pins the device choice. */
  deviceLocked: boolean
  /** The leading button: pinned sidebar ↔ Dock-style auto-hide. */
  sidebarAutoHide: boolean
  onToggleSidebarMode: () => void
}

/**
 * The persistent device strip — the Mac's `DeviceBarView`.
 *
 * The sidebar button leads, then the status icon carrying the colour and the
 * tooltip, then the pill that opens the dropdown; a wireless device gets a
 * disconnect button beside it, and Run on all appears only when it would mean
 * something. The Mac's bundle pill and mirror shortcut are absent because their
 * subsystems are: `docs/desktop-parity.md` says which item each waits on.
 */
export function DeviceBar(props: DeviceBarProps) {
  const [sheet, setSheet] = useState<WirelessMode | null>(null)

  return (
    <div className="flex h-[46px] shrink-0 items-center gap-2.5 border-b border-border-subtle bg-bg-chrome px-3">
      <IconButton
        label={
          props.sidebarAutoHide
            ? "Pin the sidebar (auto-hide is on — hover the left edge to peek)"
            : "Auto-hide the sidebar (Ctrl+B shows it on demand)"
        }
        onClick={props.onToggleSidebarMode}
      >
        {props.sidebarAutoHide ? <PanelLeftDashed size={15} /> : <PanelLeft size={15} />}
      </IconButton>
      <StatusIcon device={props.selected} />
      <DeviceControl bar={props} onWireless={setSheet} />

      <AdbWarning />

      <span className="flex-1" />

      {props.showsRunAll ? (
        <div
          className="flex items-center gap-1.5"
          title="Run this feature on every connected device"
        >
          <Layers size={13} className={props.runOnAll ? "text-accent" : "text-text-tertiary"} />
          <span className="text-text-secondary">Run on all</span>
          <Switch
            checked={props.runOnAll}
            onChange={props.onRunOnAll}
            ariaLabel="Run on all devices"
          />
        </div>
      ) : null}

      {/* Top-right, so the toasts drop from underneath it — which is what
          makes the two surfaces read as one thing on the Mac. */}
      <NotificationBell />

      {sheet === null ? null : (
        <WirelessSheet
          mode={sheet}
          devices={props.devices}
          onSelectDevice={props.onSelect}
          onDismiss={() => {
            setSheet(null)
          }}
        />
      )}
    </div>
  )
}

/** The pill, its dropdown, and the two buttons that sit beside them. */
function DeviceControl({
  bar,
  onWireless,
}: {
  bar: DeviceBarProps
  onWireless: (mode: WirelessMode) => void
}) {
  const { avds, launch, disconnect } = useDeviceBarActions(bar.devices)
  const [menuOpen, setMenuOpen] = useState(false)
  const selected = bar.selected
  return (
    <div className="relative flex items-center gap-2.5">
      <DevicePill
        device={selected}
        open={menuOpen}
        disabled={bar.deviceLocked}
        onToggle={() => {
          setMenuOpen((open) => !open)
        }}
      />
      {menuOpen ? (
        <DeviceMenu
          devices={bar.devices}
          selected={selected}
          avds={avds}
          disabled={bar.deviceLocked}
          onSelect={bar.onSelect}
          onLaunchAvd={launch}
          onPair={() => {
            onWireless("pair")
          }}
          onConnect={() => {
            onWireless("connect")
          }}
          onManageEmulators={() => {
            bar.onOpenFeature("emulators")
          }}
          onDismiss={() => {
            setMenuOpen(false)
          }}
        />
      ) : null}

      {bar.devices.length === 0 ? (
        <Empty loaded={bar.devicesLoaded} onRefresh={bar.onRefresh} />
      ) : null}

      {selected?.isWireless === true ? (
        <IconButton
          label={`Disconnect ${selected.label}`}
          tone="danger"
          onClick={() => {
            disconnect(selected)
          }}
        >
          <WifiOff size={14} />
        </IconButton>
      ) : null}
    </div>
  )
}

/** Nothing attached: say so, and offer to look again. */
function Empty({ loaded, onRefresh }: { loaded: boolean; onRefresh: () => Promise<void> }) {
  const [refreshing, setRefreshing] = useState(false)
  return (
    <>
      <span className="text-text-secondary">
        {loaded ? "Connect one over USB or Wi-Fi" : "Looking for devices…"}
      </span>
      <IconButton
        label="Refresh devices"
        spinning={refreshing}
        onClick={() => {
          // The stream publishes on change, so a device that never shows up
          // produces nothing to wait for. This asks adb outright.
          setRefreshing(true)
          void onRefresh().finally(() => {
            setRefreshing(false)
          })
        }}
      >
        <RefreshCw size={14} />
      </IconButton>
    </>
  )
}

