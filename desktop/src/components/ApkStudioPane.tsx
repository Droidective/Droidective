import { FileArchive } from "lucide-react"
import { useState } from "react"

import { ApkInspectorPane } from "@/components/ApkInspectorPane"
import { ApkSignPane } from "@/components/ApkSignPane"
import { ApkStudioChooser } from "@/components/ApkStudioChooser"
import { DecompilePane } from "@/components/DecompilePane"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, pickFile } from "@/lib/daemon"
import { STUDIO_TABS, type StudioTab } from "@/lib/apk-studio"

/**
 * APK Studio — the Mac's `ApkStudioView`.
 *
 * One workspace over one loaded APK: Inspect · Decompile · Sign, each the same
 * screen the standalone feature shows, handed the APK rather than asking for
 * it. That is the point of the hub — the Mac folds the three standalone tools
 * into it, and once this app has the hub they fold in here too (`lib/hubs.ts`).
 *
 * Recompile is not a fourth tab: apktool's rebuild belongs to the tree it
 * rebuilds, so it lives on the Decompile tab's toolbar where the Mac also
 * keeps it within reach of the sources. Naming it as a tab with nothing of its
 * own to show would be a tab that redirects.
 */
export function ApkStudioPane() {
  const { show } = useNotifications()
  const [apk, setApk] = useState<string | null>(null)
  const [tab, setTab] = useState<StudioTab>("inspect")

  const choose = () => {
    void (async () => {
      try {
        const picked = await pickFile("APK", ["apk"])
        // A dismissed dialog is a choice, not a failure.
        if (picked !== null) setApk(picked)
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
      }
    })()
  }

  if (apk === null) return <ApkStudioChooser onChoose={choose} />

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex shrink-0 items-center gap-1 border-b border-border-subtle px-3 py-2">
        {STUDIO_TABS.map((one) => (
          <button
            key={one.id}
            type="button"
            onClick={() => setTab(one.id)}
            className={`rounded px-2 py-1 ${
              tab === one.id
                ? "bg-bg-surface text-text-primary"
                : "text-text-secondary hover:bg-bg-surface"
            }`}
          >
            {one.title}
          </button>
        ))}
        <div className="ml-auto flex min-w-0 items-center gap-2">
          <FileArchive size={12} className="shrink-0 text-text-tertiary" />
          <span className="truncate text-text-tertiary" title={apk}>
            {apk.split("/").pop()}
          </span>
          <button
            type="button"
            onClick={choose}
            className="shrink-0 rounded border border-border-subtle px-2 py-1 text-text-secondary hover:bg-bg-surface"
          >
            Change…
          </button>
        </div>
      </div>
      {/* All three stay mounted: switching tabs must not re-run a decompile
          that took a minute, and the Mac's studio keeps their state too. The
          hidden ones are display:none rather than unmounted. */}
      <div className="min-h-0 flex-1">
        <Slot active={tab === "inspect"}>
          <ApkInspectorPane apkPath={apk} />
        </Slot>
        <Slot active={tab === "decompile"}>
          <DecompilePane apkPath={apk} />
        </Slot>
        <Slot active={tab === "sign"}>
          <ApkSignPane apkPath={apk} />
        </Slot>
      </div>
    </div>
  )
}

/**
 * One tab's contents, kept mounted while another is showing.
 *
 * `hidden` rather than unmounting, for the reason the app's own tab strip does
 * it: a decompile is slow enough that losing it on a tab switch would make the
 * studio worse than three separate screens.
 */
function Slot({ active, children }: { active: boolean; children: React.ReactNode }) {
  return (
    <div className={active ? "h-full" : "hidden"} aria-hidden={!active}>
      {children}
    </div>
  )
}
