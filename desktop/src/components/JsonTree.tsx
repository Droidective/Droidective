import { useMemo, useState } from "react"
import { ChevronDown, ChevronRight, Copy, Search, Type } from "lucide-react"
import { cn } from "@/lib/cn"
import { copyText } from "@/lib/daemon"
import { jsonMatches, type TreeMatch } from "@/lib/json-search"
import { copyValue } from "@/lib/reactotron-copy"
import {
  emptyTreeState,
  pathKey,
  pathsTo,
  rowPreview,
  toggled,
  treeRows,
  type TreeRow,
  type TreeState,
} from "@/lib/json-tree"
import type { JsonValue } from "@/lib/json"

/** How many results the find bar lists before it asks for a narrower query. */
const MAX_RESULTS = 200

/**
 * The object tree: a payload as collapsible rows, with find-in-object over it.
 *
 * Which rows exist and in what order lives in `lib/json-tree.ts`, and the search
 * in `lib/json-search.ts` — the two agree on one ordinal path scheme, which is
 * what lets a clicked result open its ancestors and land on the row it named.
 */
export function JsonTree({ value, findable = true }: { value: JsonValue; findable?: boolean }) {
  const [state, setState] = useState<TreeState>(emptyTreeState)
  const [query, setQuery] = useState("")
  const rows = useMemo(() => treeRows(value, state), [value, state])
  const matches = useMemo(
    () =>
      query.trim() === ""
        ? []
        : jsonMatches(value, query, { limit: MAX_RESULTS, expandingStringifiedJson: true }),
    [value, query],
  )
  const found = useMemo(() => new Set(matches.map((match) => pathKey(match.path))), [matches])

  // The root's own row is dropped when it has children — they are what the
  // reader wants, and a "{ 12 }" line above them says nothing. A scalar payload
  // has no children, so its root row is the only thing there is to show.
  const shown = rows.filter((row) => row.depth > 0 || !row.isContainer)

  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      {findable ? <FindBar query={query} onQuery={setQuery} /> : null}
      {query.trim() === "" ? null : (
        <Results
          matches={matches}
          onReveal={(match) => {
            setState((current) => ({
              ...current,
              // Its ancestors too: a result three levels down is useless if the
              // reader has to find the way in.
              expanded: new Set([...current.expanded, ...pathsTo(match.path)]),
            }))
          }}
        />
      )}
      <div className="flex min-w-0 flex-col">
        {shown.map((row) => (
          <Row
            key={row.key}
            row={row}
            highlighted={found.has(row.key)}
            onToggle={() => {
              setState((current) => ({ ...current, expanded: toggled(current.expanded, row.key) }))
            }}
            onToggleRaw={() => {
              setState((current) => ({ ...current, raw: toggled(current.raw, row.key) }))
            }}
          />
        ))}
      </div>
    </div>
  )
}

function FindBar({ query, onQuery }: { query: string; onQuery: (query: string) => void }) {
  return (
    <div className="flex items-center gap-2 rounded-md border border-border-subtle bg-bg-root px-2 focus-within:border-accent">
      <Search size={11} className="shrink-0 text-text-tertiary" />
      <input
        value={query}
        aria-label="Find in this object"
        placeholder="Find in this object…"
        onChange={(event) => {
          onQuery(event.target.value)
        }}
        onKeyDown={(event) => {
          if (event.key === "Escape") onQuery("")
        }}
        className="min-w-0 flex-1 bg-transparent py-1 font-mono text-[11px] text-text-primary outline-none placeholder:text-text-tertiary"
      />
    </div>
  )
}

function Results({
  matches,
  onReveal,
}: {
  matches: TreeMatch[]
  onReveal: (match: TreeMatch) => void
}) {
  if (matches.length === 0) {
    return <p className="px-1 text-[11px] text-text-tertiary">No matches</p>
  }
  return (
    <div className="flex max-h-[140px] flex-col overflow-y-auto rounded-md bg-bg-root py-0.5">
      {matches.map((match) => (
        <button
          key={match.displayPath}
          type="button"
          onClick={() => {
            onReveal(match)
          }}
          className="flex min-w-0 items-baseline gap-2 px-2 py-0.5 text-left hover:bg-bg-raised"
        >
          <span className="shrink-0 font-mono text-[10.5px] text-rt-key">{match.displayPath}</span>
          <span className="min-w-0 truncate font-mono text-[10.5px] text-text-tertiary">
            {match.preview}
          </span>
        </button>
      ))}
      {matches.length >= MAX_RESULTS ? (
        <p className="px-2 py-0.5 text-[10.5px] text-text-tertiary">
          …first {MAX_RESULTS} matches — narrow the search
        </p>
      ) : null}
    </div>
  )
}

/** Points per nesting level, matching `JSONTreeLayout.indentPerDepth`. */
const INDENT = 12

function Row({
  row,
  highlighted,
  onToggle,
  onToggleRaw,
}: {
  row: TreeRow
  highlighted: boolean
  onToggle: () => void
  onToggleRaw: () => void
}) {
  const [copied, setCopied] = useState(false)
  const Chevron = row.isExpanded ? ChevronDown : ChevronRight
  return (
    <div
      className={cn(
        "group flex min-w-0 items-baseline gap-1.5 rounded-sm py-px",
        highlighted ? "bg-accent/15" : "",
      )}
      style={{ paddingLeft: Math.max(0, row.depth - 1) * INDENT }}
    >
      <button
        type="button"
        onClick={onToggle}
        disabled={!row.isContainer}
        title={row.isContainer ? (row.isExpanded ? "Collapse" : "Expand") : undefined}
        aria-label={row.isContainer ? `Toggle ${row.label}` : row.label}
        aria-expanded={row.isContainer ? row.isExpanded : undefined}
        className="flex size-3.5 shrink-0 items-center justify-center text-text-tertiary disabled:opacity-0"
      >
        <Chevron size={11} />
      </button>
      {row.label === "" ? null : (
        <span className="shrink-0 font-mono text-[11px] text-rt-key">{row.label}</span>
      )}
      <span
        className={cn("min-w-0 flex-1 truncate font-mono text-[11px]", valueTone(row))}
        title={rowPreview(row, 2000)}
        data-selectable
      >
        {rowPreview(row)}
      </span>
      {/* A stringified payload shows as its object; this is the way back to the
          text the app actually sent — an encoded token or a signed blob is only
          readable raw. */}
      {row.isParsed ? (
        <button
          type="button"
          onClick={onToggleRaw}
          title="Show the raw string the app sent"
          aria-label="Show the raw string"
          className="shrink-0 text-text-tertiary opacity-0 group-hover:opacity-100 hover:text-text-primary"
        >
          <Type size={11} />
        </button>
      ) : null}
      <button
        type="button"
        onClick={() => {
          void copyText(copyValue(row)).then(() => {
            setCopied(true)
            setTimeout(() => {
              setCopied(false)
            }, 1200)
          })
        }}
        title="Copy this value"
        aria-label="Copy this value"
        className={cn(
          "shrink-0 hover:text-text-primary",
          copied ? "text-accent" : "text-text-tertiary opacity-0 group-hover:opacity-100",
        )}
      >
        <Copy size={11} />
      </button>
    </div>
  )
}

/** Reactotron's own value colours: orange numbers, coral for null. */
function valueTone(row: TreeRow): string {
  if (row.isContainer) return "text-text-secondary"
  if (row.value === null) return "text-rt-special"
  if (typeof row.value === "number" || typeof row.value === "boolean") return "text-rt-number"
  return "text-text-primary"
}
