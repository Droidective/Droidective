import { TriangleAlert } from "lucide-react"
import { useToolchain } from "@/hooks/useToolchain"
import { openUrl } from "@/lib/daemon"

/**
 * adb is not on this machine — the Mac's own warning, in its place on the bar.
 *
 * Nothing works without adb, so this is the one tool status worth a permanent
 * spot rather than a Doctor visit. The link opens the download page; neither app
 * ever installs a tool itself. Nothing is shown until adb has actually been
 * looked for, so the bar cannot flash a warning during startup.
 */
export function AdbWarning() {
  const { adbMissing } = useToolchain()
  if (adbMissing !== true) return null
  return (
    <span className="flex items-center gap-1.5 pl-1">
      <TriangleAlert size={13} className="shrink-0 text-warn" />
      <span className="text-warn">adb not found</span>
      <button
        type="button"
        onClick={() => {
          void openUrl("https://developer.android.com/tools/releases/platform-tools")
        }}
        title="adb ships with Android platform-tools — install it via Android Studio or this download page, then re-check in Settings ▸ Doctor"
        className="text-[11.5px] text-text-tertiary underline hover:text-text-primary"
      >
        How to install
      </button>
    </span>
  )
}
