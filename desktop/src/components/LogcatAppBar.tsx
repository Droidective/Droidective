import { Crosshair } from "lucide-react"
import { Select } from "@/components/Controls"
import { cn } from "@/lib/cn"
import { appFilterLabel, type AppFilter } from "@/lib/logcat-app"

/**
 * Which app the log is narrowed to.
 *
 * The Mac picks from its saved bundles; this app has no bundle store, so it
 * follows the one app selection it does have — the Apps tab's — which is what
 * every other per-app screen here already uses. One selector rather than two,
 * which is the Mac's own arrangement (it hides the device bar's bundle pill on
 * this screen for the same reason).
 *
 * The state is said out loud rather than left to an empty feed: "waiting for an
 * app" and "that app is quiet" look identical, and only one of them means
 * something is about to happen.
 */
export function LogcatAppBar({
  appFilter,
  packageId,
  canNarrow,
  narrowed,
  onNarrow,
  onUseForegroundApp,
}: {
  appFilter: AppFilter
  packageId: string | null
  canNarrow: boolean
  narrowed: boolean
  onNarrow: (narrowed: boolean) => void
  onUseForegroundApp: () => void
}) {
  return (
    <div className="flex items-center gap-2 px-3 pb-2">
      <span className="shrink-0 text-[11.5px] text-text-tertiary">App</span>
      <div className="w-[220px] shrink-0">
        <Select
          value={narrowed ? "app" : "all"}
          options={[
            { value: "all", label: "All apps" },
            {
              value: "app",
              // Named even when nothing is chosen, so the option explains why
              // it cannot be picked instead of reading as a missing feature.
              label: packageId ?? "Pick an app in Apps first",
            },
          ]}
          onChange={(value) => {
            if (value === "app" && !canNarrow) return
            onNarrow(value === "app")
          }}
        />
      </div>
      <button
        type="button"
        onClick={onUseForegroundApp}
        title="Narrow to whatever is on the device screen"
        className="flex shrink-0 items-center gap-1 rounded-md bg-bg-raised px-2 py-1 text-[11.5px] text-text-secondary hover:bg-border-subtle hover:text-text-primary"
      >
        <Crosshair size={12} />
        App on screen
      </button>
      {narrowed ? (
        <span
          className={cn(
            "min-w-0 truncate text-[11.5px]",
            appFilter.kind === "waiting" ? "text-warn" : "text-text-tertiary",
          )}
        >
          {appFilterLabel(appFilter)}
        </span>
      ) : null}
    </div>
  )
}

