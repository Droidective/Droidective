import { Search } from "lucide-react"
import { useEffect, useState } from "react"

import { Banner, Button } from "@/components/Controls"
import { searchApps, sortApps } from "@/lib/apps"
import { asDaemonError, listApps } from "@/lib/daemon"
import type { AppSummary, DaemonError } from "@/lib/wire"

/**
 * Pick an installed app — the Mac's `InstalledAppsPickerView`.
 *
 * Opened from anywhere that needs an app but is not the Apps screen: the Mac
 * opens it from the device bar's bundle pill and from Logcat's app menu, and
 * for the same reason both times — walking to another screen to choose one, and
 * losing your place there, is the step worth not having.
 *
 * The same search as the Apps list (`searchApps`/`sortApps`), so a query that
 * finds an app in one finds it in the other. System packages are behind the
 * same switch, off by default.
 */
export function InstalledAppsPicker({
  serial,
  onPick,
  onCancel,
}: {
  serial: string
  onPick: (packageId: string) => void
  onCancel: () => void
}) {
  const [apps, setApps] = useState<AppSummary[]>([])
  const [error, setError] = useState<DaemonError | null>(null)
  const [query, setQuery] = useState("")
  const [includeSystem, setIncludeSystem] = useState(false)

  useEffect(() => {
    let cancelled = false
    listApps(serial).then(
      (response) => {
        if (!cancelled) setApps(response.apps)
      },
      (thrown: unknown) => {
        if (!cancelled) setError(asDaemonError(thrown))
      },
    )
    return () => {
      cancelled = true
    }
  }, [serial])

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onCancel()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onCancel])

  const visible = sortApps(searchApps(apps, query, includeSystem))

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Cancel"
        onClick={onCancel}
        className="absolute inset-0 cursor-default"
      />
      <dialog
        open
        aria-modal="true"
        aria-label="Installed apps"
        className="relative flex h-[460px] w-[480px] max-w-full flex-col overflow-hidden rounded-xl border border-border-subtle bg-bg-raised text-text-primary shadow-2xl"
      >
        <header className="flex shrink-0 items-center gap-2 border-b border-border-subtle px-3 py-2.5">
          <Search size={12} className="shrink-0 text-text-tertiary" />
          <input
            autoFocus
            value={query}
            placeholder="Search name, version, or bundle…"
            aria-label="Search installed apps"
            onChange={(event) => {
              setQuery(event.target.value)
            }}
            className="min-w-0 flex-1 bg-transparent text-text-primary outline-none placeholder:text-text-tertiary"
          />
          <Button onClick={onCancel}>Cancel</Button>
        </header>

        <AppChoices apps={apps} visible={visible} error={error} onPick={onPick} />

        <footer className="flex shrink-0 items-center gap-2 border-t border-border-subtle px-3 py-2">
          <label className="flex items-center gap-1.5 text-[11.5px] text-text-secondary">
            <input
              type="checkbox"
              checked={includeSystem}
              onChange={(event) => {
                setIncludeSystem(event.target.checked)
              }}
              className="accent-accent"
            />
            Include system apps
          </label>
          <span className="ml-auto text-[11.5px] text-text-tertiary">
            {visible.length} of {apps.length}
          </span>
        </footer>
      </dialog>
    </div>
  )
}

/** The rows, or why there are none yet. */
function AppChoices({
  apps,
  visible,
  error,
  onPick,
}: {
  apps: readonly AppSummary[]
  visible: readonly AppSummary[]
  error: DaemonError | null
  onPick: (packageId: string) => void
}) {
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      {error === null ? null : (
        <div className="p-3">
          <Banner tone="error">{error.message}</Banner>
        </div>
      )}
      {error === null && apps.length === 0 && (
        <p className="p-3 text-text-tertiary">Reading installed apps…</p>
      )}
      {visible.map((app) => (
        <button
          key={app.packageId}
          type="button"
          onClick={() => {
            onPick(app.packageId)
          }}
          className="flex w-full flex-col items-start gap-0.5 px-3 py-1.5 text-left hover:bg-bg-hover"
        >
          <span className="text-text-primary">{app.displayName}</span>
          <span className="text-[11.5px] text-text-tertiary">
            {app.packageId}
            {app.versionName === null ? "" : ` · ${app.versionName}`}
            {app.isSystem ? " · system app" : ""}
          </span>
        </button>
      ))}
    </div>
  )
}
