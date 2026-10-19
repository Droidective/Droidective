import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react"
import { ConfirmDialog } from "@/components/ConfirmDialog"
import { linkCutQuestion, type LinkCutQuestion } from "@/lib/tailnet"
import type { Device, FeatureSummary } from "@/lib/wire"

interface RemoteLink {
  /** Feature id → the registry's sentence for how it can cut the link. */
  warnings: ReadonlyMap<string, string>
  /** Every connected device, so the question can name the phone. */
  devices: readonly Device[]
}

const RemoteLinkContext = createContext<RemoteLink>({ warnings: new Map(), devices: [] })

/**
 * What the window knows about link-cutting features — the registry's
 * `remoteLinkWarning`s and the devices they might run on.
 *
 * A context for the reason the run targets are one: a Wi-Fi toggle, a
 * developer setting and the wireless sheet each need to ask, and none of them
 * is handed the registry. Outside a window (a test, the Quick Actions panel)
 * nothing is flagged and nothing asks.
 */
export function RemoteLinkProvider({
  features,
  devices,
  children,
}: {
  features: readonly FeatureSummary[]
  devices: readonly Device[]
  children: ReactNode
}) {
  const warnings = useMemo(() => {
    const map = new Map<string, string>()
    for (const feature of features) {
      const warning = feature.remoteLinkWarning
      if (warning !== null && warning !== undefined) map.set(feature.id, warning)
    }
    return map
  }, [features])
  const value = useMemo<RemoteLink>(() => ({ warnings, devices }), [warnings, devices])
  return <RemoteLinkContext value={value}>{children}</RemoteLinkContext>
}

interface Pending extends LinkCutQuestion {
  confirmLabel: string
  run: () => void
}

/**
 * Ask before a feature that can take a phone off the network runs on one
 * reached over Tailscale — the Mac's link-cut confirmation.
 *
 * `ask` runs at once when there is nothing to ask; otherwise it holds the run
 * behind a `ConfirmDialog` whose confirm button names the action. A cancel
 * drops it, so a control that only changes when the run happens stays where it
 * was. Render `dialog` somewhere in the screen.
 */
export function useRemoteLinkGuard(): {
  ask: (
    featureId: string,
    serials: readonly string[],
    confirmLabel: string,
    run: () => void,
  ) => void
  dialog: ReactNode
} {
  const { warnings, devices } = useContext(RemoteLinkContext)
  const [pending, setPending] = useState<Pending | null>(null)

  const ask = useCallback(
    (featureId: string, serials: readonly string[], confirmLabel: string, run: () => void) => {
      const question = linkCutQuestion(warnings.get(featureId), serials, devices)
      if (question === null) {
        run()
        return
      }
      setPending({ ...question, confirmLabel, run })
    },
    [warnings, devices],
  )

  const dialog =
    pending === null ? null : (
      <ConfirmDialog
        title={pending.title}
        message={pending.message}
        confirmLabel={pending.confirmLabel}
        onConfirm={() => {
          setPending(null)
          pending.run()
        }}
        onCancel={() => {
          setPending(null)
        }}
      />
    )

  return { ask, dialog }
}
