import { Crosshair, PlusSquare } from "lucide-react"
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
 * this screen for the same reason). The Mac's remaining bundle verb,
 * "Add manually / manage…", has nothing to manage here and is not offered.
 *
 * The state is said out loud rather than left to an empty feed: "waiting for an
 * app" and "that app is quiet" look identical, and only one of them means
 * something is about to happen.
 */
export function LogcatAppBar({
  appFilter,
  packageId,
  canNarrow,
  canPick,
  narrowed,
  onNarrow,
  onUseForegroundApp,
  onAddFromInstalled,
}: {
  appFilter: AppFilter
  packageId: string | null
  canNarrow: boolean
  /** Whether a device is there to read an app list off. */
  canPick: boolean
  narrowed: boolean
  onNarrow: (narrowed: boolean) => void
  onUseForegroundApp: () => void
  onAddFromInstalled: () => void
}) {
  return (
    <div className="flex items-center gap-2 px-3 pb-2">
      <span className="shrink-0 text-[11.5px] text-text-tertiary">App</span>
      {/* The Mac's tooltip on the same picker: nothing else says a saved
          bundle is what fills it. */}
      <div className="w-[220px] shrink-0" title="Stream one app's logs — pick a saved bundle or add a new one">
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
        onClick={onAddFromInstalled}
        disabled={!canPick}
        // The Mac's wording and its place in the menu: right before "Use app on
        // device screen", which is the other way to answer the same question.
        title="Choose from the apps installed on the device"
        className="flex shrink-0 items-center gap-1 rounded-md bg-bg-raised px-2 py-1 text-[11.5px] text-text-secondary hover:bg-border-subtle hover:text-text-primary disabled:cursor-not-allowed disabled:opacity-40"
      >
        <PlusSquare size={12} />
        Add from installed apps
      </button>
      <button
        type="button"
        onClick={onUseForegroundApp}
        // The Mac's tooltip; its label is "Use app on device screen", which is
        // what the button says now — "App on screen" left it ambiguous whether
        // it *reads* the screen or filters to it.
        title="Narrow to whatever is on the device screen"
        className="flex shrink-0 items-center gap-1 rounded-md bg-bg-raised px-2 py-1 text-[11.5px] text-text-secondary hover:bg-border-subtle hover:text-text-primary"
      >
        <Crosshair size={12} />
        Use app on device screen
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

