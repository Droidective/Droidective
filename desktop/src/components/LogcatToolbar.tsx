import { Download, Filter, Search, X } from "lucide-react"
import { Select } from "@/components/Controls"
import { cn } from "@/lib/cn"
import { LogcatAppBar as AppBar } from "@/components/LogcatAppBar"
import type { AppFilter } from "@/lib/logcat-app"
import { LEVELS, type Level, type LogFilter } from "@/lib/logbuffer"

const LEVEL_NAMES: Record<Level, string> = {
  V: "Verbose",
  D: "Debug",
  I: "Info",
  W: "Warn",
  E: "Error",
  F: "Fatal",
}

/**
 * Filter, Find, level, tags, export.
 *
 * Filter and Find are deliberately two fields, as they are on the Mac: "show me
 * only this" and "where is this?" are different questions, and one box that did
 * both would answer neither well.
 */
export function LogcatToolbar({
  filter,
  onFilter,
  find,
  onFind,
  hits,
  tags,
  onExport,
  appFilter,
  packageId,
  canNarrow,
  narrowed,
  onNarrow,
  onUseForegroundApp,
}: {
  filter: LogFilter
  onFilter: (filter: LogFilter) => void
  find: string
  onFind: (find: string) => void
  hits: number
  tags: string[]
  onExport: () => void
  /** What the log is actually narrowed to right now. */
  appFilter: AppFilter
  /** The app chosen in Apps, which is what narrowing follows. */
  packageId: string | null
  canNarrow: boolean
  narrowed: boolean
  onNarrow: (narrowed: boolean) => void
  onUseForegroundApp: () => void
}) {
  return (
    <div className="shrink-0 border-b border-border-subtle bg-bg-chrome">
      <FilterRow
        filter={filter}
        onFilter={onFilter}
        find={find}
        onFind={onFind}
        hits={hits}
        onExport={onExport}
      />

      <AppBar
        appFilter={appFilter}
        packageId={packageId}
        canNarrow={canNarrow}
        narrowed={narrowed}
        onNarrow={onNarrow}
        onUseForegroundApp={onUseForegroundApp}
      />

      <TagBar
        chosen={filter.tags}
        tags={tags}
        onToggle={(tag) => {
          onFilter({
            ...filter,
            tags: filter.tags.includes(tag)
              ? filter.tags.filter((entry) => entry !== tag)
              : [...filter.tags, tag],
          })
        }}
        onClear={() => {
          onFilter({ ...filter, tags: [] })
        }}
      />
    </div>
  )
}

/**
 * Filter, Find, the level floor, and export.
 *
 * Filter and Find are deliberately two fields, as they are on the Mac: "show me
 * only this" and "where is this?" are different questions, and one box that did
 * both would answer neither well.
 */
function FilterRow({
  filter,
  onFilter,
  find,
  onFind,
  hits,
  onExport,
}: {
  filter: LogFilter
  onFilter: (filter: LogFilter) => void
  find: string
  onFind: (find: string) => void
  hits: number
  onExport: () => void
}) {
  return (
    <div className="flex items-center gap-2 px-3 py-2">
      <Field
        icon={Filter}
        value={filter.text}
        label="Filter lines"
        placeholder="Filter — hides the rest…"
        onChange={(text) => {
          onFilter({ ...filter, text })
        }}
      />
      <Field
        icon={Search}
        value={find}
        label="Find in the log"
        placeholder="Find — highlights only…"
        onChange={onFind}
      />
      {find.trim() === "" ? null : (
        <span className="shrink-0 text-[11.5px] text-text-tertiary">
          {hits.toLocaleString()} {hits === 1 ? "hit" : "hits"}
        </span>
      )}

      <div className="w-[124px] shrink-0">
        <Select
          value={filter.minLevel}
          options={LEVELS.map((level) => ({ value: level, label: LEVEL_NAMES[level] }))}
          onChange={(value) => {
            onFilter({ ...filter, minLevel: value as Level })
          }}
        />
      </div>

      <button
        type="button"
        onClick={onExport}
        title="Export what is shown to ~/Downloads/Droidective"
        aria-label="Export the log"
        className="flex size-7 shrink-0 items-center justify-center rounded-md bg-bg-raised text-text-secondary hover:bg-border-subtle hover:text-text-primary"
      >
        <Download size={13} />
      </button>
    </div>
  )
}

/**
 * The tag chips.
 *
 * Chosen tags always show; the rest are the most frequent in the buffer, which
 * is the only ranking that puts the tag you are looking for near the front of a
 * log with hundreds of them.
 */
function TagBar({
  chosen,
  tags,
  onToggle,
  onClear,
}: {
  chosen: readonly string[]
  tags: string[]
  onToggle: (tag: string) => void
  onClear: () => void
}) {
  const offered = [...chosen, ...tags.filter((tag) => !chosen.includes(tag))].slice(0, 16)
  if (offered.length === 0) return null
  return (
    <div className="flex items-center gap-1.5 overflow-x-auto px-3 pb-2">
      {chosen.length === 0 ? null : (
        <button
          type="button"
          onClick={onClear}
          className="flex shrink-0 items-center gap-1 rounded-full bg-bg-raised px-2 py-0.5 text-[11px] text-text-secondary hover:text-text-primary"
        >
          <X size={9} strokeWidth={3} />
          All tags
        </button>
      )}
      {offered.map((tag) => (
        <button
          key={tag}
          type="button"
          onClick={() => {
            onToggle(tag)
          }}
          className={cn(
            "shrink-0 rounded-full px-2 py-0.5 text-[11px] transition-colors",
            chosen.includes(tag)
              ? "bg-accent/20 text-accent"
              : "bg-bg-raised text-text-tertiary hover:text-text-primary",
          )}
        >
          {tag}
        </button>
      ))}
    </div>
  )
}

function Field({
  icon: Icon,
  value,
  label,
  placeholder,
  onChange,
}: {
  icon: typeof Search
  value: string
  label: string
  placeholder: string
  onChange: (value: string) => void
}) {
  return (
    <div className="flex min-w-0 flex-1 items-center gap-2 rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1 focus-within:border-accent">
      <Icon size={13} className="shrink-0 text-text-tertiary" />
      <input
        value={value}
        aria-label={label}
        placeholder={placeholder}
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
