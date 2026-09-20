/**
 * The JS Console's filter bar: the text filter, the level picker and export.
 *
 * Its own file rather than part of `JsConsoleParts` because that one is at
 * oxlint's line ceiling, which is the repo's cue to split.
 */

import { ChevronDown, ListFilter, TextSearch, Trash2, Upload } from "lucide-react"
import { useRef, useState } from "react"

import { RowSelectionMenu } from "@/components/RowSelectionMenu"
import { useDismissOnOutside } from "@/hooks/useDismissOnOutside"
import type { ConsoleExport } from "@/hooks/useConsoleExport"
import type { ConsoleSelection } from "@/hooks/useConsoleSelection"
import { allHidden, LEVELS, levelSummary, toggleLevel, type Level } from "@/lib/console-feed"
import { cn } from "@/lib/cn"

export function Filters({
  hidden,
  counts,
  query,
  onQuery,
  onHidden,
  onClear,
  exporting,
  onFind,
  selection,
}: {
  hidden: ReadonlySet<Level>
  counts: Record<Level, number>
  query: string
  onQuery: (value: string) => void
  onHidden: (hidden: ReadonlySet<Level>) => void
  onClear: () => void
  exporting: ConsoleExport
  onFind: () => void
  selection: ConsoleSelection
}) {
  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle px-3 py-1.5">
      <input
        value={query}
        // The Mac's placeholder, without the ellipsis it never had.
        placeholder="Filter"
        onChange={(event) => onQuery(event.target.value)}
        className="min-w-0 flex-1 rounded border border-border-subtle bg-bg-surface px-2 py-1 text-text-primary"
      />
      {selection.count === 0 ? null : (
        <RowSelectionMenu
          count={selection.count}
          noun="logs"
          onCopy={selection.copy}
          onCopyAsJson={selection.copyAsJson}
          onDeselect={selection.clear}
        />
      )}
      <button
        type="button"
        // The Mac's tooltip, with Ctrl for its ⌘ — the standing exception.
        title="Find & highlight in console (Ctrl+F)"
        aria-label="Find in console"
        onClick={onFind}
        className="shrink-0 rounded p-1 text-text-secondary hover:bg-bg-surface"
      >
        <TextSearch size={13} />
      </button>
      <LevelPicker hidden={hidden} counts={counts} onHidden={onHidden} />
      <ExportMenu exporting={exporting} />
      <button
        type="button"
        title="Clear the console"
        onClick={onClear}
        className="shrink-0 rounded p-1 text-text-secondary hover:bg-bg-surface"
      >
        <Trash2 size={13} />
      </button>
    </div>
  )
}

/**
 * The Mac's level filter: a pill that says how much is hidden, opening a
 * popover of checkboxes with Show All and Hide All under a rule.
 *
 * This used to be a row of per-level chips — which is the design the Mac
 * *replaced*, and it filtered the other way round as well (see `FilterState`).
 * Four chips fit; the pill is what keeps the bar from growing a chip per level
 * and is what someone moving between the two apps will look for.
 */
function LevelPicker({
  hidden,
  counts,
  onHidden,
}: {
  hidden: ReadonlySet<Level>
  counts: Record<Level, number>
  onHidden: (hidden: ReadonlySet<Level>) => void
}) {
  const [open, setOpen] = useState(false)
  const box = useRef<HTMLDivElement | null>(null)
  useDismissOnOutside(box, setOpen)

  return (
    <div ref={box} className="relative shrink-0">
      <button
        type="button"
        title="Choose which log levels to show"
        aria-expanded={open}
        onClick={() => {
          setOpen(!open)
        }}
        className={cn(
          "flex items-center gap-1.5 rounded-full border border-border-subtle px-2 py-0.5 text-text-secondary hover:text-text-primary",
          hidden.size > 0 && "bg-bg-raised text-text-primary",
        )}
      >
        <ListFilter size={12} />
        {levelSummary(hidden)}
        <ChevronDown size={11} />
      </button>
      {open ? (
        <div className="absolute top-full right-0 z-40 mt-1 w-[190px] rounded-md border border-border-subtle bg-bg-raised p-3 shadow-2xl">
          <p className="mb-2 font-semibold text-text-tertiary">Show levels</p>
          {LEVELS.map((level) => (
            <label key={level} className="flex cursor-pointer items-center gap-2 py-0.5">
              <input
                type="checkbox"
                checked={!hidden.has(level)}
                onChange={() => {
                  onHidden(toggleLevel(hidden, level))
                }}
              />
              <span className="capitalize text-text-primary">{level}</span>
              {counts[level] > 0 ? (
                <span className="ml-auto text-text-tertiary">{counts[level]}</span>
              ) : null}
            </label>
          ))}
          <div className="mt-2 flex items-center justify-between border-t border-border-subtle pt-2">
            <button
              type="button"
              disabled={hidden.size === 0}
              onClick={() => {
                onHidden(new Set())
              }}
              className="text-accent enabled:hover:underline disabled:opacity-40"
            >
              Show All
            </button>
            <button
              type="button"
              disabled={hidden.size === LEVELS.length}
              onClick={() => {
                onHidden(allHidden())
              }}
              className="text-accent enabled:hover:underline disabled:opacity-40"
            >
              Hide All
            </button>
          </div>
        </div>
      ) : null}
    </div>
  )
}

/** Save as JSON… / Copy to Clipboard, over exactly the rows on screen. */
function ExportMenu({ exporting }: { exporting: ConsoleExport }) {
  const [open, setOpen] = useState(false)
  const box = useRef<HTMLDivElement | null>(null)
  useDismissOnOutside(box, setOpen)

  const pick = (run: () => void) => {
    setOpen(false)
    run()
  }

  return (
    <div ref={box} className="relative shrink-0">
      <button
        type="button"
        title="Export the filtered console — save as a JSON file or copy to the clipboard"
        aria-label="Export"
        aria-expanded={open}
        disabled={!exporting.enabled}
        onClick={() => {
          setOpen(!open)
        }}
        className="rounded p-1 text-text-secondary enabled:hover:bg-bg-surface disabled:opacity-40"
      >
        <Upload size={13} />
      </button>
      {open ? (
        <div
          role="menu"
          className="absolute top-full right-0 z-40 mt-1 min-w-[170px] rounded-md border border-border-subtle bg-bg-raised py-1 shadow-2xl"
        >
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              pick(exporting.saveAsJson)
            }}
            className="w-full px-3 py-1 text-left text-text-primary hover:bg-accent/20"
          >
            Save as JSON…
          </button>
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              pick(exporting.copyToClipboard)
            }}
            className="w-full px-3 py-1 text-left text-text-primary hover:bg-accent/20"
          >
            Copy to Clipboard
          </button>
        </div>
      ) : null}
    </div>
  )
}
