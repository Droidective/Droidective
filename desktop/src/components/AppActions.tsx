import { useState } from "react"
import { Button } from "@/components/Controls"
import { ConfirmDialog } from "@/components/screen"
import { useNotifications } from "@/hooks/useNotifications"
import { actionLabel, destructivePrompt } from "@/lib/apps"
import { asDaemonError, controlApp } from "@/lib/daemon"
import type { AppActionDescriptor } from "@/lib/wire"

/**
 * The verbs a package can be put through — Open, Restart, Force Stop,
 * Minimize, Clear Cache, Clear Data, Uninstall.
 *
 * Shared by the Apps explorer's detail pane and the standalone Manage App
 * screen, because on the Mac those two show the same controls over the same
 * `AppControlService.AppAction` set, and the daemon sends the list rather than
 * either side hardcoding it.
 *
 * A destructive verb opens a **dialog**, not an armed button. That is the Mac's
 * shape — `confirmationDialog` in both `AppsExplorerView` and
 * `AppManagementView` — and the port's rule is that a dialog stays a dialog;
 * the earlier arm-then-press pattern here was a difference someone had to
 * relearn, and it stated the consequence nowhere.
 */
export function AppActions({
  actions,
  packageId,
  serial,
}: {
  actions: AppActionDescriptor[]
  packageId: string
  serial: string
}) {
  const { show } = useNotifications()
  const [running, setRunning] = useState<string | null>(null)
  const [confirming, setConfirming] = useState<AppActionDescriptor | null>(null)

  const run = (action: AppActionDescriptor) => {
    setRunning(action.id)
    void (async () => {
      try {
        const outcome = await controlApp({ serial, packageId, action: action.id })
        show({
          message: outcome.message,
          ok: outcome.ok,
          ...(outcome.copyText === null ? {} : { copyText: outcome.copyText }),
          ...(outcome.revealPath === null ? {} : { revealPath: outcome.revealPath }),
        })
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
      } finally {
        setRunning(null)
      }
    })()
  }

  return (
    <>
      <div className="flex flex-wrap items-center gap-2">
        {actions.map((action) => (
          <Button
            key={action.id}
            tone={action.isDestructive ? "danger" : "default"}
            disabled={running !== null}
            onClick={() => {
              // The daemon says which verbs are destructive, so this side never
              // has its own opinion about what deserves a second look.
              if (action.isDestructive) {
                setConfirming(action)
                return
              }
              run(action)
            }}
          >
            {running === action.id ? "Running…" : actionLabel(action)}
          </Button>
        ))}
      </div>

      {confirming === null ? null : (
        <ConfirmDialog
          title={destructivePrompt(confirming, packageId)}
          confirmLabel={actionLabel(confirming)}
          onConfirm={() => {
            const action = confirming
            setConfirming(null)
            run(action)
          }}
          onCancel={() => {
            setConfirming(null)
          }}
        />
      )}
    </>
  )
}
