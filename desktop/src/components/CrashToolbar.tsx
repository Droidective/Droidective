import { Copy, Download, Eye, RefreshCw, Search, Trash2 } from "lucide-react"
import { Button, Select } from "@/components/Controls"
import { useArmedConfirm } from "@/hooks/useArmedConfirm"
import { cn } from "@/lib/cn"
import { CRASH_FORMATS, presentKinds, presentProcesses, type CrashFilters } from "@/lib/crashes"
import type { CrashFormat } from "@/lib/crashes"
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

      <ClearButton onClear={onClear} />
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

/** Emptying the device's buffer is not undoable, so it takes a second press. */
function ClearButton({ onClear }: { onClear: () => void }) {
  const confirm = useArmedConfirm()
  const armed = confirm.isArmed("clear", "crash-buffer")
  return (
    <Button
      tone="danger"
      onClick={() => {
        if (!armed) {
          confirm.arm("clear", "crash-buffer")
          return
        }
        confirm.disarm()
        onClear()
      }}
      title="Clear the device's crash buffer — this can't be undone"
    >
      <span className={cn("flex items-center gap-1.5")}>
        <Trash2 size={13} />
        {armed ? "Really clear the buffer?" : "Clear"}
      </span>
    </Button>
  )
}
