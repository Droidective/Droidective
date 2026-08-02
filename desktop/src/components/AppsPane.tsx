import { useCallback, useEffect, useMemo, useState } from "react"
import { Boxes, RefreshCw, Search } from "lucide-react"
import { Banner, Button, Switch } from "@/components/Controls"
import { actionLabel, searchApps, sortApps } from "@/lib/apps"
import { asDaemonError, controlApp, listApps } from "@/lib/daemon"
import { cn } from "@/lib/cn"
import type {
  AppActionDescriptor,
  AppSummary,
  DaemonError,
  Device,
  RunResponse,
} from "@/lib/wire"

/**
 * The installed-app browser, and the verbs that act on one.
 *
 * The selected app is lifted to the caller because it is not local to this
 * screen: a `needsBundle` action in the palette needs the same choice, the
 * way the Mac app's selected bundle feeds `AppState.run`.
 */
export function AppsPane({
  device,
  selected,
  onSelect,
}: {
  device: Device | null
  selected: string | null
  onSelect: (packageId: string | null) => void
}) {
  const [apps, setApps] = useState<AppSummary[]>([])
  const [actions, setActions] = useState<AppActionDescriptor[]>([])
  const [query, setQuery] = useState("")
  const [includeSystem, setIncludeSystem] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<DaemonError | null>(null)

  const serial = device?.serial ?? null
  const load = useCallback(async () => {
    if (serial === null) return
    setLoading(true)
    setError(null)
    try {
      const response = await listApps(serial)
      setApps(response.apps)
      setActions(response.actions)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    } finally {
      setLoading(false)
    }
  }, [serial])

  // A full `dumpsys package packages` parse, so it is fetched on open rather
  // than polled. Clearing the selection is deliberately *not* done here: this
  // pane remounts on every tab switch, and resetting on mount would throw
  // away a choice the palette is still using. The device change that really
  // invalidates it is handled where the state lives.
  useEffect(() => {
    setApps([])
    void load()
  }, [load])

  const visible = useMemo(
    () => sortApps(searchApps(apps, query, includeSystem)),
    [apps, query, includeSystem],
  )
  const current = apps.find((app) => app.packageId === selected) ?? null

  if (!device) {
    return <p className="p-6 text-text-tertiary">Connect a device to browse its apps.</p>
  }

  return (
    <div className="flex min-h-0 flex-1">
      <AppList
        apps={visible}
        query={query}
        onQuery={setQuery}
        includeSystem={includeSystem}
        onIncludeSystem={setIncludeSystem}
        loading={loading}
        loaded={apps.length > 0}
        selected={selected}
        onSelect={onSelect}
        onRefresh={() => void load()}
      />

      <div className="min-w-0 flex-1 bg-bg-root">
        {error ? (
          <div className="p-6">
            <Banner tone="error">
              {error.message}
              {error.detail ? <div className="mt-1 opacity-70">{error.detail}</div> : null}
            </Banner>
          </div>
        ) : current ? (
          <AppDetail key={current.packageId} app={current} actions={actions} serial={device.serial} />
        ) : (
          <p className="p-6 text-text-tertiary">Pick an app.</p>
        )}
      </div>
    </div>
  )
}

/** The searchable app list. Its own component only so `AppsPane` stays legible. */
function AppList({
  apps,
  query,
  onQuery,
  includeSystem,
  onIncludeSystem,
  loading,
  loaded,
  selected,
  onSelect,
  onRefresh,
}: {
  apps: AppSummary[]
  query: string
  onQuery: (value: string) => void
  includeSystem: boolean
  onIncludeSystem: (value: boolean) => void
  loading: boolean
  loaded: boolean
  selected: string | null
  onSelect: (packageId: string) => void
  onRefresh: () => void
}) {
  return (
      <aside className="flex w-[340px] shrink-0 flex-col border-r border-border-subtle bg-bg-chrome">
        <div className="flex items-center gap-2 px-3 py-2.5">
          <div className="flex flex-1 items-center gap-2 rounded-lg bg-bg-raised px-2.5 py-1.5 focus-within:ring-1 focus-within:ring-accent/60">
            <Search size={13} className="shrink-0 text-text-tertiary" />
            <input
              value={query}
              aria-label="Search apps"
              placeholder={`Search ${String(apps.length)} apps…`}
              onChange={(event) => {
                onQuery(event.target.value)
              }}
              className="min-w-0 flex-1 bg-transparent text-[13px] text-text-primary outline-none placeholder:text-text-tertiary"
            />
          </div>
          <Button onClick={onRefresh} disabled={loading} title="Refresh">
            <RefreshCw size={13} className={loading ? "animate-spin" : undefined} />
          </Button>
        </div>
        <div className="px-3 pb-2">
          <Switch checked={includeSystem} onChange={onIncludeSystem} label="System apps" />
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto pb-2">
          {loading && !loaded ? (
            <p className="px-4 py-8 text-center text-text-tertiary">Reading the package list…</p>
          ) : apps.length === 0 ? (
            <p className="px-4 py-8 text-center text-text-tertiary">No apps match.</p>
          ) : (
            apps.map((app) => (
              <button
                key={app.packageId}
                type="button"
                onClick={() => {
                  onSelect(app.packageId)
                }}
                className={cn(
                  "flex w-full items-start gap-2.5 px-4 py-1.5 text-left transition-colors",
                  app.packageId === selected ? "bg-accent/12" : "hover:bg-white/[0.04]",
                )}
              >
                <Boxes size={17} className="mt-[3px] shrink-0 text-accent" />
                <span className="min-w-0">
                  <span className="block truncate text-[13.5px] text-text-primary">
                    {app.displayName}
                    {app.isSystem ? (
                      <span className="ml-1.5 text-[10.5px] uppercase tracking-wide text-text-tertiary">
                        system
                      </span>
                    ) : null}
                  </span>
                  <span className="block truncate text-[11.5px] text-text-secondary">
                    {app.packageId}
                    {app.versionName === null ? "" : ` · ${app.versionName}`}
                  </span>
                </span>
              </button>
            ))
          )}
        </div>
      </aside>
  )
}

function AppDetail({
  app,
  actions,
  serial,
}: {
  app: AppSummary
  actions: AppActionDescriptor[]
  serial: string
}) {
  const [running, setRunning] = useState<string | null>(null)
  const [confirming, setConfirming] = useState<string | null>(null)
  const [result, setResult] = useState<RunResponse | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)

  const run = async (action: AppActionDescriptor) => {
    // A second press for the destructive ones, matching the Quick Actions
    // panel's second-⏎ rule. The daemon says which those are.
    if (action.isDestructive && confirming !== action.id) {
      setConfirming(action.id)
      return
    }
    setConfirming(null)
    setRunning(action.id)
    setResult(null)
    setError(null)
    try {
      setResult(await controlApp({ serial, packageId: app.packageId, action: action.id }))
    } catch (thrown) {
      setError(asDaemonError(thrown))
    } finally {
      setRunning(null)
    }
  }

  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto p-6">
      <header className="flex items-start gap-3">
        <Boxes size={22} className="mt-0.5 shrink-0 text-accent" />
        <div className="min-w-0">
          <h2 className="text-[17px] font-semibold text-text-primary" data-selectable>
            {app.displayName}
          </h2>
          <p className="mt-0.5 text-text-secondary" data-selectable>
            {app.packageId}
            {app.versionName === null ? "" : ` · ${app.versionName}`}
            {app.isSystem ? " · system app" : ""}
          </p>
        </div>
      </header>

      <div className="flex flex-wrap gap-2">
        {actions.map((action) => (
          <Button
            key={action.id}
            tone={action.isDestructive ? "danger" : "default"}
            disabled={running !== null}
            onClick={() => void run(action)}
          >
            {running === action.id
              ? "Running…"
              : confirming === action.id
                ? `Really ${actionLabel(action).toLowerCase()}?`
                : actionLabel(action)}
          </Button>
        ))}
      </div>

      {error ? (
        <Banner tone="error">
          {error.message}
          {error.detail ? <div className="mt-1 opacity-70">{error.detail}</div> : null}
        </Banner>
      ) : null}
      {result ? <Banner tone={result.ok ? "ok" : "error"}>{result.message}</Banner> : null}
    </div>
  )
}
