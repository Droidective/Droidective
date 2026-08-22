import { useCallback, useEffect, useState } from "react"
import { Download } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { HubColumn, HubRowList, HubSection } from "@/components/Hub"
import { NoBundle, NotInstalled } from "@/components/NoBundle"
import { NoDevice } from "@/components/screen"
import { useNotifications } from "@/hooks/useNotifications"
import { appInfo, asDaemonError, pullApk } from "@/lib/daemon"
import { infoRows, pulledApkMessage } from "@/lib/appinfo"
import type { AppInfoResponse, DaemonError, Device } from "@/lib/wire"

/**
 * Version, SDK, install dates and APK size — the Mac's `AppInfoView`.
 *
 * Two sections: the rows, and a Pull APK button. The pull answers where every
 * file landed, splits included, because an App Bundle install saves more than
 * the one file the button implies.
 */
export function AppInfoPane({ device, packageId }: { device: Device | null; packageId: string | null }) {
  const { show } = useNotifications()
  const [info, setInfo] = useState<AppInfoResponse | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)
  const [pulling, setPulling] = useState(false)

  const serial = device?.serial ?? null
  const load = useCallback(async () => {
    if (serial === null || packageId === null) return
    setError(null)
    try {
      setInfo(await appInfo(serial, packageId))
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [packageId, serial])

  useEffect(() => {
    setInfo(null)
    void load()
  }, [load])

  if (!device) return <NoDevice feature="app-info" title="App Info" />
  if (packageId === null) return <NoBundle what="see its app info" />

  if (error !== null) {
    return (
      <div className="p-5">
        <Banner tone="error">{error.message}</Banner>
      </div>
    )
  }
  if (info === null) return <p className="p-5 text-text-tertiary">Reading app info…</p>
  if (!info.installed) return <NotInstalled packageId={packageId} />

  const pull = () => {
    if (serial === null) return
    setPulling(true)
    void (async () => {
      try {
        const result = await pullApk(serial, packageId)
        const landed = result.paths.at(-1)
        show({
          ok: true,
          message: pulledApkMessage(result.paths),
          ...(landed === undefined ? {} : { revealPath: landed }),
        })
      } catch (thrown) {
        show({ ok: false, message: asDaemonError(thrown).message })
      } finally {
        setPulling(false)
      }
    })()
  }

  return (
    <HubColumn>
      <HubSection title="App info">
        <HubRowList rows={infoRows(info)} />
      </HubSection>
      <HubSection title="APK">
        <div>
          <Button tone="primary" onClick={pull} disabled={pulling}>
            <span className="flex items-center gap-1.5">
              <Download size={12} />
              {pulling ? "Pulling…" : "Pull APK"}
            </span>
          </Button>
        </div>
      </HubSection>
    </HubColumn>
  )
}
