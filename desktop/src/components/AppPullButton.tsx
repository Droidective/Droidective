import { Download } from "lucide-react"
import { useState } from "react"

import { Button } from "@/components/Controls"
import { useNotifications } from "@/hooks/useNotifications"
import { pulledApkMessage } from "@/lib/appinfo"
import { asDaemonError, pullApk } from "@/lib/daemon"

/**
 * Pull an installed app's APK off the device.
 *
 * Shared by App Info and the Apps explorer, both of which offer it on the Mac,
 * so the toast — including how a split install's extra files are counted — is
 * written once.
 */
export function AppPullButton({ serial, packageId }: { serial: string; packageId: string }) {
  const { show } = useNotifications()
  const [pulling, setPulling] = useState(false)

  return (
    <Button
      tone="primary"
      disabled={pulling}
      onClick={() => {
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
      }}
    >
      <span className="flex items-center gap-1.5">
        <Download size={12} />
        {pulling ? "Pulling…" : "Pull APK"}
      </span>
    </Button>
  )
}
