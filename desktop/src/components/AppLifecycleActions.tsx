import { Eye, EyeOff, Undo2 } from "lucide-react"
import { useState } from "react"

import { ConfirmDialog } from "@/components/ConfirmDialog"
import { Button } from "@/components/Controls"
import { useNotifications } from "@/hooks/useNotifications"
import { appLifecycle, asDaemonError } from "@/lib/daemon"
import type { AppSummary } from "@/lib/wire"

/**
 * The Mac's Manage section: Disable / Enable, or Restore.
 *
 * Which one is offered is the app's own state, not a pair of always-present
 * buttons — a package removed for this user cannot be disabled, and offering it
 * would be a button that fails. That is the Mac's arrangement too.
 *
 * Every verb here is reversible and per-user (`pm disable-user` / `pm enable`,
 * `pm uninstall --user 0` / `cmd package install-existing`); none touches the
 * system image, so none needs root. Disabling still asks, because an app that
 * vanishes from the launcher with no explanation is alarming even when getting
 * it back is one button away.
 */
export function AppLifecycleActions({
  app,
  serial,
  onChanged,
}: {
  app: AppSummary
  serial: string
  /** Re-read the list: the state shown here is what the list carries. */
  onChanged: () => void
}) {
  const { show } = useNotifications()
  const [busy, setBusy] = useState(false)
  const [confirming, setConfirming] = useState(false)

  const write = (change: { disabled?: boolean; removed?: boolean }) => {
    setBusy(true)
    appLifecycle({ serial, packageId: app.packageId, ...change })
      .then(
        (result) => {
          show({ message: result.message, ok: result.ok })
          if (result.ok) onChanged()
        },
        (thrown: unknown) => {
          show({ message: asDaemonError(thrown).message, ok: false })
        },
      )
      .finally(() => {
        setBusy(false)
      })
  }

  if (app.removed) {
    return (
      <Button
        tone="primary"
        disabled={busy}
        onClick={() => {
          write({ removed: false })
        }}
      >
        <span className="flex items-center gap-1.5">
          <Undo2 size={12} />
          Restore
        </span>
      </Button>
    )
  }

  return (
    <>
      <Button
        disabled={busy}
        onClick={() => {
          // Enabling needs no question: it puts something back.
          if (app.disabled) write({ disabled: false })
          else setConfirming(true)
        }}
      >
        <span className="flex items-center gap-1.5">
          {app.disabled ? <Eye size={12} /> : <EyeOff size={12} />}
          {app.disabled ? "Enable" : "Disable"}
        </span>
      </Button>
      {confirming && (
        <ConfirmDialog
          title={`Disable ${app.displayName}?`}
          message="It disappears from the launcher and stops running until you enable it again. Nothing is uninstalled."
          confirmLabel="Disable"
          onConfirm={() => {
            setConfirming(false)
            write({ disabled: true })
          }}
          onCancel={() => {
            setConfirming(false)
          }}
        />
      )}
    </>
  )
}
