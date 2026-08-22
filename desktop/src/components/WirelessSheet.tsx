import { useEffect, useState } from "react"
import { Check, CircleX, Wifi } from "lucide-react"
import { Button } from "@/components/Controls"
import { WirelessSteps } from "@/components/WirelessSteps"
import { ConnectTab, UsbTab } from "@/components/WirelessTabs"
import { useWirelessActions, type Status } from "@/hooks/useWirelessActions"
import { cn } from "@/lib/cn"
import type { Device } from "@/lib/wire"

/** Which path the sheet opens on, and what each tab is called. */
export type WirelessMode = "pair" | "connect" | "usb"

const TABS: readonly { readonly id: WirelessMode; readonly label: string }[] = [
  { id: "pair", label: "Pair new device" },
  { id: "connect", label: "Already paired" },
  { id: "usb", label: "Via USB cable" },
]

/**
 * Getting a device onto wireless adb — the Mac's `WirelessConnectSheet`.
 *
 * Three paths, one per tab, with its wording: first-time Android 11+ pairing
 * (code plus the *pairing* port, then connect), a plain connect for an
 * already-paired device, and the one-click USB→Wi-Fi bootstrap. Endpoints are
 * single paste-friendly "ip:port" fields, exactly as the phone displays them,
 * and the daemon parses them — `ConnectionService.parseEndpoint` is the
 * authority on what adb takes, so this side only decides when a button lights
 * up (`lib/endpoint.ts`).
 */
export function WirelessSheet({
  mode: initialMode,
  devices,
  onSelectDevice,
  onDismiss,
}: {
  mode: WirelessMode
  devices: Device[]
  /** A newly reachable device becomes the selected one, as on the Mac. */
  onSelectDevice: (serial: string) => void
  onDismiss: () => void
}) {
  const [mode, setMode] = useState<WirelessMode>(initialMode)
  const actions = useWirelessActions({ onSelectDevice, onDismiss })

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onDismiss])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Close"
        onClick={onDismiss}
        className="absolute inset-0 cursor-default"
      />
      <dialog
        open
        aria-label="Connect over Wi-Fi"
        className={cn(
          "relative m-0 flex w-[470px] max-w-full flex-col gap-3.5 p-5",
          "rounded-xl border border-border-subtle bg-bg-raised text-text-primary shadow-2xl",
        )}
      >
        <Header />

        <div className="flex gap-1 rounded-lg bg-bg-root p-1">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              type="button"
              disabled={actions.busy}
              onClick={() => {
                setMode(tab.id)
                actions.clearStatus()
              }}
              className={cn(
                "flex-1 rounded-md px-2 py-1 text-[12.5px] disabled:opacity-50",
                mode === tab.id
                  ? "bg-bg-raised text-text-primary"
                  : "text-text-secondary hover:text-text-primary",
              )}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {mode === "pair" ? <WirelessSteps actions={actions} /> : null}

        {mode === "connect" ? (
          <ConnectTab
            endpoint={actions.endpoint}
            busy={actions.busy}
            onEndpoint={actions.setEndpoint}
            onConnect={() => {
              actions.connect(actions.endpoint)
            }}
          />
        ) : null}

        {mode === "usb" ? (
          <UsbTab devices={devices} busy={actions.busy} onSwitch={actions.switchToWifi} />
        ) : null}

        <div className="h-px bg-border-subtle" />

        <div className="flex items-start gap-2">
          <StatusLine busy={actions.busy} status={actions.status} />
          <span className="flex-1" />
          <Button onClick={onDismiss}>Close</Button>
        </div>
      </dialog>
    </div>
  )
}

function Header() {
  return (
    <header className="flex items-start gap-3">
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-accent/12 text-accent">
        <Wifi size={17} />
      </span>
      <div className="min-w-0">
        <h2 className="text-[14px] font-medium text-text-primary">Connect over Wi-Fi</h2>
        <p className="mt-0.5 text-[12px] text-text-secondary">
          Debug without a cable. The device and this computer must be on the same Wi-Fi network.
        </p>
      </div>
    </header>
  )
}

function StatusLine({ busy, status }: { busy: boolean; status: Status | null }) {
  if (busy) return <span className="text-[12px] text-text-tertiary">Working…</span>
  if (status === null) return null
  return (
    <p
      className={cn(
        "flex min-w-0 items-start gap-1.5 text-[12px]",
        status.ok ? "text-text-primary" : "text-danger",
      )}
      data-selectable
    >
      <span className={cn("mt-px shrink-0", status.ok ? "text-accent" : "text-danger")}>
        {status.ok ? <Check size={13} /> : <CircleX size={13} />}
      </span>
      {status.message}
    </p>
  )
}
