import { useState } from "react"
import { ListRestart, RefreshCw, ScrollText, TriangleAlert, XOctagon } from "lucide-react"
import { Button, TextInput } from "@/components/Controls"
import { DeepLinksSection } from "@/components/DeepLinksSection"
import { HubActionCard, HubLinkRow } from "@/components/HubActionCard"
import { HubColumn, HubSection } from "@/components/Hub"
import { useHubAction, type HubActions } from "@/hooks/useHubAction"
import { useTargets } from "@/hooks/useTargets"
import type { Device } from "@/lib/wire"

/**
 * The React Native hub — the Mac's `ReactNativeView`, section for section.
 *
 * Dev menu, JS reload and process death as quick-action cards; the two ways to
 * reach Metro (the USB `adb reverse` and the Wi-Fi dev host); the saved deep
 * links; and links to the three screens RN work leans on. The gathered actions
 * stay searchable and hotkey-able — this only puts them in one place so the
 * sidebar is not a wall of RN tools.
 *
 * Nothing here re-implements an action: every button hands its values to the
 * same `run_action` route the generated form uses (`useHubAction`).
 */
export function ReactNativeHubPane({
  device,
  packageId,
  onOpen,
}: {
  device: Device | null
  packageId: string | null
  onOpen: (id: string) => void
}) {
  const actions = useHubAction(device)
  const { serials } = useTargets()
  const ready = serials.length > 0

  return (
    <HubColumn>
      <QuickActions actions={actions} ready={ready} />
      <MetroSection actions={actions} ready={ready} />
      <DeepLinksSection packageId={packageId} />

      <HubSection title="Related tools">
        <div className="flex flex-col">
          <HubLinkRow
            id="logcat"
            title="Logcat"
            detail="Live JS & native logs"
            icon={ScrollText}
            first
            onOpen={onOpen}
          />
          <HubLinkRow
            id="crash-catcher"
            title="Crash Catcher"
            detail="Catches ReactNativeJS crashes"
            icon={TriangleAlert}
            onOpen={onOpen}
          />
          <HubLinkRow
            id="performance"
            title="Performance Monitor"
            detail="Live CPU, RAM & FPS"
            icon={RefreshCw}
            onOpen={onOpen}
          />
        </div>
      </HubSection>
    </HubColumn>
  )
}

function QuickActions({ actions, ready }: { actions: HubActions; ready: boolean }) {
  /** Disabled with nothing connected, or while *its own* action is in flight. */
  const disabled = (id: string) => !ready || actions.runningId === id

  return (
    <HubSection
      title="Quick actions"
      subtitle="One-click commands for the dev build on the selected device."
    >
      <div className="grid grid-cols-[repeat(auto-fit,minmax(220px,1fr))] gap-2.5">
        <HubActionCard
          title="Reload JS"
          detail="Reload the JS bundle — like pressing R twice"
          icon={RefreshCw}
          prominent
          help="Sends R·R (keycode 46) — needs an RN dev build with the app in front"
          disabled={disabled("reload-js")}
          running={actions.runningId === "reload-js"}
          onClick={() => {
            actions.run("reload-js")
          }}
        />
        <HubActionCard
          title="Dev Menu"
          detail="Open the in-app developer menu"
          icon={ListRestart}
          help="Sends keycode 82 — needs an RN dev build with the app in front"
          disabled={disabled("open-dev-menu")}
          running={actions.runningId === "open-dev-menu"}
          onClick={() => {
            actions.run("open-dev-menu")
          }}
        />
        <HubActionCard
          title="Process Death"
          detail="Background, then kill the app to test state restore"
          icon={XOctagon}
          help="Backgrounds then kills the selected app — or the app in front when none is chosen"
          disabled={disabled("process-death")}
          running={actions.runningId === "process-death"}
          onClick={() => {
            actions.run("process-death")
          }}
        />
      </div>
      {ready ? null : <p className="text-text-tertiary">Connect a device to use these.</p>}
    </HubSection>
  )
}

/**
 * The two ways the app on the device reaches Metro on this machine, in the
 * Mac's order: the USB tunnel first, because it is the one that needs no
 * network at all.
 */
function MetroSection({ actions, ready }: { actions: HubActions; ready: boolean }) {
  const [metroPort, setMetroPort] = useState("8081")
  const [devHost, setDevHost] = useState("")

  return (
    <HubSection
      title="Metro bundler"
      subtitle="Connect the app on the device to the bundler running on this machine."
    >
      <MetroPath
        transport="USB"
        label="Forward the Metro port"
        caption="adb reverse tunnels the device port to this machine. Metro serves on 8081 by default."
      >
        <div className="w-[120px]">
          <TextInput
            value={metroPort}
            onChange={setMetroPort}
            placeholder="8081"
            ariaLabel="Metro port"
          />
        </div>
        <Button
          tone="primary"
          disabled={!ready || actions.runningId === "reverse-port" || metroPort.trim() === ""}
          onClick={() => {
            actions.run("reverse-port", { port: metroPort.trim() })
          }}
        >
          Forward
        </Button>
      </MetroPath>

      <div className="border-t border-border-subtle" />

      <MetroPath
        transport="WI-FI"
        label="Set the dev server host"
        caption={
          "localhost tunnels the Metro port to this machine; a remote host is set on the " +
          "device where Android allows it, otherwise the dev menu opens with directions."
        }
      >
        <div className="w-[260px]">
          <TextInput
            value={devHost}
            onChange={setDevHost}
            placeholder="192.168.1.10:8081"
            ariaLabel="Dev server host"
          />
        </div>
        <Button
          tone="primary"
          disabled={!ready || actions.runningId === "rn-dev-host" || devHost.trim() === ""}
          onClick={() => {
            actions.run("rn-dev-host", { host: devHost.trim() })
          }}
        >
          Set
        </Button>
      </MetroPath>
    </HubSection>
  )
}

/**
 * One Metro transport path: an eyebrow naming the transport, what the control
 * does, a one-line explanation, then the field and its button.
 */
function MetroPath({
  transport,
  label,
  caption,
  children,
}: {
  transport: string
  label: string
  caption: string
  children: React.ReactNode
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center gap-2">
        <span className="rounded bg-accent/10 px-1.5 py-0.5 text-[11px] font-semibold text-accent">
          {transport}
        </span>
        <span className="text-text-primary">{label}</span>
      </div>
      <p className="text-[11.5px] text-text-tertiary">{caption}</p>
      <div className="flex items-center gap-2.5 pt-0.5">{children}</div>
    </div>
  )
}
