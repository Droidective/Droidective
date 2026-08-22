import { useCallback, useEffect, useState } from "react"
import { Banner } from "@/components/Controls"
import { AppActions } from "@/components/AppActions"
import { NoBundle } from "@/components/NoBundle"
import { NoDevice } from "@/components/screen"
import { asDaemonError, listApps } from "@/lib/daemon"
import type { AppActionDescriptor, AppSummary, DaemonError, Device } from "@/lib/wire"

/**
 * Open, restart, stop, minimize, clear or uninstall the chosen app — the Mac's
 * `AppManagementView`.
 *
 * The same verbs as the Apps explorer's detail pane, because on the Mac they
 * are the same set over the same service; this screen is the standalone way in
 * when Apps is not the tab you are on. The list of verbs comes from the daemon
 * with the app list, so neither screen decides it.
 */
export function ManageAppPane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  const [actions, setActions] = useState<AppActionDescriptor[]>([])
  const [app, setApp] = useState<AppSummary | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)

  const serial = device?.serial ?? null
  const load = useCallback(async () => {
    if (serial === null || packageId === null) return
    setError(null)
    try {
      const response = await listApps(serial)
      setActions(response.actions)
      setApp(response.apps.find((entry) => entry.packageId === packageId) ?? null)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [packageId, serial])

  useEffect(() => {
    setApp(null)
    void load()
  }, [load])

  if (!device) return <NoDevice feature="app-management" title="Manage App" />
  if (packageId === null) return <NoBundle what="manage it" />

  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto p-6">
      {error === null ? null : <Banner tone="error">{error.message}</Banner>}

      <header className="min-w-0">
        <h2 className="text-[15px] font-semibold text-text-primary" data-selectable>
          {app?.displayName ?? packageId}
        </h2>
        <p className="mt-0.5 text-[11.5px] text-text-tertiary" data-selectable>
          {packageId}
          {app?.versionName === undefined || app.versionName === null
            ? ""
            : ` · ${app.versionName}`}
        </p>
      </header>

      {actions.length === 0 ? (
        <p className="text-text-tertiary">Reading the app…</p>
      ) : (
        <AppActions actions={actions} packageId={packageId} serial={device.serial} />
      )}
    </div>
  )
}
