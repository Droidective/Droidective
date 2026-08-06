import { CornerLeftUp, File, Folder } from "lucide-react"
import { cn } from "@/lib/cn"
import { formatBytes } from "@/lib/files"
import type { FileEntry } from "@/lib/wire"

/**
 * One folder's contents.
 *
 * A folder's name is a button and opens on a click; a file's name is text.
 * The Mac needs a double-click there because single-click is how its `List`
 * selects, but here the checkbox owns selection, so the click is free — and a
 * name that is a real button is one a screen reader and a keyboard can reach.
 * The row still opens on a double-click, for anyone arriving from the Mac.
 */
export function FileList({
  entries,
  selection,
  atRoot,
  onUp,
  onOpen,
  onToggle,
  onContextMenu,
}: {
  entries: FileEntry[] | null
  selection: ReadonlySet<string>
  atRoot: boolean
  onUp: () => void
  onOpen: (entry: FileEntry) => void
  onToggle: (name: string) => void
  onContextMenu: (entry: FileEntry, x: number, y: number) => void
}) {
  if (entries === null) return <Filler>Reading files…</Filler>
  if (entries.length === 0 && atRoot) return <Filler>Empty folder.</Filler>

  return (
    <div className="min-h-0 flex-1 overflow-y-auto py-1" data-selectable>
      {atRoot ? null : (
        <button
          type="button"
          onClick={onUp}
          className="flex w-full items-center gap-2.5 px-3 py-1 text-left text-[13px] text-text-secondary hover:bg-white/[0.04]"
        >
          <span className="w-[13px]" />
          <CornerLeftUp size={15} className="shrink-0 text-text-tertiary" />
          ..
        </button>
      )}
      {entries.length === 0 ? (
        <p className="px-4 py-8 text-center text-text-tertiary">Empty folder.</p>
      ) : (
        entries.map((entry) => (
          <Row
            key={entry.name}
            entry={entry}
            checked={selection.has(entry.name)}
            onOpen={() => {
              onOpen(entry)
            }}
            onToggle={() => {
              onToggle(entry.name)
            }}
            onContextMenu={(x, y) => {
              onContextMenu(entry, x, y)
            }}
          />
        ))
      )}
    </div>
  )
}

function Row({
  entry,
  checked,
  onOpen,
  onToggle,
  onContextMenu,
}: {
  entry: FileEntry
  checked: boolean
  onOpen: () => void
  onToggle: () => void
  onContextMenu: (x: number, y: number) => void
}) {
  return (
    // A group, not a button: the checkbox inside it is its own control, and a
    // button inside a button is invalid.
    <div
      className={cn(
        "flex items-center gap-2.5 px-3 py-1 text-[13px]",
        checked ? "bg-accent/12" : "hover:bg-white/[0.04]",
      )}
      onDoubleClick={onOpen}
      onContextMenu={(event) => {
        event.preventDefault()
        onContextMenu(event.clientX, event.clientY)
      }}
    >
      <input
        type="checkbox"
        checked={checked}
        aria-label={`Select ${entry.name}`}
        title="Add to selection"
        onChange={onToggle}
        className="h-[13px] w-[13px] shrink-0 accent-[var(--color-accent)]"
      />
      {entry.isDir ? (
        <button
          type="button"
          onClick={onOpen}
          title={`Open ${entry.name}`}
          className="flex min-w-0 flex-1 items-center gap-2.5 text-left"
        >
          <Folder size={15} className="shrink-0 text-accent" />
          <span className="truncate text-text-primary">{entry.name}</span>
        </button>
      ) : (
        <span className="flex min-w-0 flex-1 items-center gap-2.5" title={entry.name}>
          <File size={15} className="shrink-0 text-text-tertiary" />
          <span className="truncate text-text-primary">{entry.name}</span>
        </span>
      )}
      <span className="shrink-0 font-mono text-[11px] text-text-tertiary">{entry.perms}</span>
      <span className="w-[84px] shrink-0 text-right tabular-nums text-text-secondary">
        {entry.isDir ? "" : formatBytes(entry.size)}
      </span>
    </div>
  )
}

function Filler({ children }: { children: string }) {
  return (
    <p className="flex min-h-0 flex-1 items-center justify-center text-text-tertiary">{children}</p>
  )
}
