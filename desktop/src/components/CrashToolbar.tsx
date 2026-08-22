
import { Copy, Download, Eye, RefreshCw, Search, Trash2, X } from "lucide-react"
import { Banner, Button, Select } from "@/components/Controls"
import { CRASH_FORMATS, presentKinds, presentProcesses, type CrashFilters } from "@/lib/crashes"
import type { CrashFormat } from "@/lib/crashes"
import type { Crashes } from "@/hooks/useCrashes"
import type { CrashReport } from "@/lib/wire"

/**
 * Refresh, Watch, the two filters, the search, and what acts on the selection.
 *
 * The Kind and Process menus list only what the current crashes actually have,
 * so no choice in them can empty the list.
 */
export function CrashToolbar({
  crashes,
  filters,
  onFilters,
  loading,
  watching,
  onWatching,
  onRefresh,
  selected,
  onCopy,
  onSave,
  onClear,
}: {
  crashes: CrashReport[]
  filters: CrashFilters
  onFilters: (filters: CrashFilters) => void
  loading: boolean
  watching: boolean
  onWatching: (on: boolean) => void
  onRefresh: () => void
  selected: CrashReport | null
  onCopy: (format: CrashFormat) => void
  onSave: () => void
  onClear: () => void
}) {
  const kinds = presentKinds(crashes)
  const processes = presentProcesses(crashes)

  return (
    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border-subtle bg-bg-chrome px-3 py-2">
      <Button onClick={onRefresh} disabled={loading} title="Fetch crashes from the device">
        <RefreshCw size={13} className={loading ? "animate-spin" : undefined} />
      </Button>

      <Button
        tone={watching ? "primary" : "default"}
        onClick={() => {
          onWatching(!watching)
        }}
        title={
          watching
            ? "Watching — checking for new crashes every 5 s. Click to stop."
            : "Watch for new crashes — checks every 5 s and says when one lands"
        }
      >
        <span className="flex items-center gap-1.5">
          <Eye size={13} className={watching ? "animate-pulse" : undefined} />
          {watching ? "Watching" : "Watch"}
        </span>
      </Button>

      {/* A menu whose every choice empties the list is worse than no menu, so
          each appears only when there is something to narrow. */}
      {kinds.length > 1 ? (
        <Narrow
          label="Kind"
          value={filters.kind}
          options={kinds.map((kind) => ({ value: kind.kind, label: kind.label }))}
          onChange={(kind) => {
            onFilters({ ...filters, kind })
          }}
        />
      ) : null}

      {processes.length > 1 ? (
        <Narrow
          label="Process"
          value={filters.process}
          options={processes.map((process) => ({ value: process, label: process }))}
          onChange={(process) => {
            onFilters({ ...filters, process })
          }}
        />
      ) : null}

      <SearchField
        value={filters.search}
        onChange={(search) => {
          onFilters({ ...filters, search })
        }}
      />

      {selected === null ? null : (
        <>
          <CopyMenu onCopy={onCopy} />
          <Button onClick={onSave} title="Save this crash to ~/Downloads/Droidective">
            <Download size={13} />
          </Button>
        </>
      )}

      {/* A trash icon that raises the confirmation, as `CrashView` does — not
          a labelled button that arms itself. */}
      <Button onClick={onClear} title="Clear the device's crash buffer">
        <Trash2 size={13} />
      </Button>
    </div>
  )
}

/** One "All, or just this one" filter. */
function Narrow({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: string | null
  options: { value: string; label: string }[]
  onChange: (value: string | null) => void
}) {
  return (
    <label className="flex items-center gap-1.5 text-text-secondary">
      {label}
      <span className="min-w-[110px]">
        <Select
          value={value ?? ""}
          options={[{ value: "", label: "All" }, ...options]}
          onChange={(next) => {
            onChange(next === "" ? null : next)
          }}
        />
      </span>
    </label>
  )
}

function SearchField({
  value,
  onChange,
}: {
  value: string
  onChange: (value: string) => void
}) {
  return (
    <div
      className="flex min-w-[160px] flex-1 items-center gap-2 rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1 focus-within:border-accent"
      title="Show only crashes containing this text"
    >
      <Search size={13} className="shrink-0 text-text-tertiary" />
      <input
        value={value}
        aria-label="Filter crashes"
        placeholder="Filter crashes…"
        onChange={(event) => {
          onChange(event.target.value)
        }}
        onKeyDown={(event) => {
          if (event.key === "Escape") onChange("")
        }}
        className="min-w-0 flex-1 bg-transparent text-[13px] text-text-primary outline-none placeholder:text-text-tertiary"
      />
    </div>
  )
}

/**
 * A `<select>` rather than a menu: the three formats are a choice, and a real
 * select is the one control a webview gets keyboard handling on for free.
 */
function CopyMenu({ onCopy }: { onCopy: (format: CrashFormat) => void }) {
  return (
    <label
      className="flex items-center gap-1.5 rounded-md bg-bg-raised px-2 py-1"
      title="Copy this crash for pasting into Slack, Jira, or anywhere"
    >
      <Copy size={13} className="text-text-secondary" />
      <select
        value=""
        aria-label="Copy this crash"
        onChange={(event) => {
          if (event.target.value !== "") onCopy(event.target.value as CrashFormat)
        }}
        className="bg-transparent text-[13px] text-text-primary outline-none"
      >
        <option value="">Copy…</option>
        {CRASH_FORMATS.map((format) => (
          <option key={format.id} value={format.id}>
            {format.label}
          </option>
        ))}
      </select>
    </label>
  )
}



/**
 * What is streaming and what arrived.
 *
 * An export's result goes to a toast now; what is left is the two states that
 * are *about the screen* rather than about something that just happened.
 */
export function CrashNotices({ crashes }: { crashes: Crashes }) {
  if (crashes.error === null && crashes.arrival === null && crashes.notice === null) return null
  return (
    <div className="flex shrink-0 flex-col gap-2 px-3 pt-3">
      {crashes.error === null ? null : (
        <Banner tone="error">
          {crashes.error.message}
          {crashes.error.detail === null ? null : (
            <div className="mt-1 opacity-70">{crashes.error.detail}</div>
          )}
        </Banner>
      )}
      {crashes.arrival === null ? null : (
        <Banner tone="warn">
          <span className="flex flex-wrap items-center gap-2">
            New crash: {crashes.arrival.title}
            <button
              type="button"
              onClick={crashes.dismiss}
              aria-label="Dismiss"
              className="text-text-tertiary hover:text-text-primary"
            >
              <X size={12} />
            </button>
          </span>
        </Banner>
      )}
      {crashes.notice === null ? null : (
        <Banner tone="ok">
          <span className="flex flex-wrap items-center gap-2">
            {crashes.notice}
            <button
              type="button"
              onClick={crashes.dismiss}
              aria-label="Dismiss"
              className="text-text-tertiary hover:text-text-primary"
            >
              <X size={12} />
            </button>
          </span>
        </Banner>
      )}
    </div>
  )
}
