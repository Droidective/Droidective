import { useState } from "react"
import { Check, TriangleAlert } from "lucide-react"

import { useToolchain } from "@/hooks/useToolchain"
import { copyText, openUrl } from "@/lib/daemon"
import { installCommand } from "@/lib/doctor"

/**
 * adb is not on this machine — the Mac's own warning, in its place on the bar.
 *
 * Nothing works without adb, so this is the one tool status worth a permanent
 * spot rather than a Doctor visit. Neither app ever installs a tool itself, so
 * the hint is the whole answer — and the hint comes from the daemon, which
 * words it for the machine it is running on: an apt command on Ubuntu, a winget
 * one on Windows, the download page on a Mac.
 *
 * Where there is a command, the button copies it. Somebody reading a tooltip
 * and retyping `sudo apt install android-tools-adb` is the version of this that
 * wastes people's time.
 */
export function AdbWarning() {
  const { adbMissing, adbHint } = useToolchain()
  const [copied, setCopied] = useState(false)
  if (adbMissing !== true) return null

  const command = installCommand(adbHint)

  return (
    <span className="flex min-w-0 items-center gap-1.5 pl-1">
      <TriangleAlert size={13} className="shrink-0 text-warn" />
      <span className="shrink-0 text-warn">adb not found</span>
      <button
        type="button"
        title={adbHint}
        onClick={() => {
          if (command === null) {
            void openUrl("https://developer.android.com/tools/releases/platform-tools")
            return
          }
          void copyText(command).then(() => {
            setCopied(true)
            setTimeout(() => {
              setCopied(false)
            }, 2000)
          })
        }}
        className="flex shrink-0 items-center gap-1 text-[11.5px] text-text-tertiary underline hover:text-text-primary"
      >
        {copied ? <Check size={11} className="text-accent" /> : null}
        {command === null ? "How to install" : copied ? "Copied" : "Copy install command"}
      </button>
    </span>
  )
}
