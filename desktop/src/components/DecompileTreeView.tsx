/**
 * The decompiled source tree's rows.
 *
 * Its own file because `DecompileBrowser` is at oxlint's line ceiling, which
 * is the repo's cue to split.
 */

import { ChevronDown, ChevronRight, FileCode, Folder, FolderOpen } from "lucide-react"
import { useMemo } from "react"

import { hitsByFile, relativePath, visibleRows } from "@/lib/decompile"
import type { DecompileHits, DecompileTree } from "@/lib/wire"

export function DecompileTreeView({
  tree,
  expanded,
  selected,
  onToggle,
  onOpen,
}: {
  tree: DecompileTree
  expanded: ReadonlySet<string>
  selected: string | null
  onToggle: (path: string) => void
  onOpen: (path: string) => void
}) {
  // Flattened rather than recursed: jadx over a real app writes tens of
  // thousands of files, and only the open ones are ever drawn.
  const rows = useMemo(() => visibleRows(tree.tree, expanded), [tree, expanded])
  return (
    <div className="py-1">
      {rows.map((row) => (
        <button
          key={row.node.path}
          type="button"
          onClick={() => (row.isDirectory ? onToggle(row.node.path) : onOpen(row.node.path))}
          style={{ paddingLeft: `${row.depth * 12 + 6}px` }}
          className={`flex w-full items-center gap-1 py-[3px] pr-2 text-left hover:bg-bg-surface ${
            selected === row.node.path ? "bg-bg-surface text-text-primary" : "text-text-secondary"
          }`}
        >
          {row.isDirectory ? (
            <>
              {row.expanded ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
              {row.expanded ? (
                <FolderOpen size={12} className="text-text-tertiary" />
              ) : (
                <Folder size={12} className="text-text-tertiary" />
              )}
            </>
          ) : (
            <FileCode size={12} className="ml-[11px] text-text-tertiary" />
          )}
          <span className="truncate">{row.node.name}</span>
        </button>
      ))}
    </div>
  )
}

export function Hits({
  root,
  hits,
  onReveal,
}: {
  root: string
  hits: DecompileHits
  onReveal: (path: string) => void
}) {
  const grouped = useMemo(() => hitsByFile(hits.hits), [hits])
  if (hits.hits.length === 0) {
    return <p className="p-3 text-text-tertiary">Nothing matched.</p>
  }
  return (
    <div className="py-1">
      {hits.capped ? (
        <p className="px-3 py-1 text-[11.5px] text-text-tertiary">
          Showing the first {hits.hits.length} matches.
        </p>
      ) : null}
      {grouped.map((group) => (
        <div key={group.path} className="mb-1">
          <button
            type="button"
            onClick={() => onReveal(group.path)}
            className="w-full truncate px-2 py-[3px] text-left text-text-primary hover:bg-bg-surface"
            title={group.path}
          >
            {relativePath(root, group.path)}
          </button>
          {group.hits.map((hit) => (
            <button
              key={`${hit.path}:${hit.line}`}
              type="button"
              onClick={() => onReveal(hit.path)}
              className="flex w-full gap-2 px-2 py-[2px] pl-5 text-left hover:bg-bg-surface"
            >
              <span className="shrink-0 tabular-nums text-text-tertiary">{hit.line}</span>
              <span className="truncate font-mono text-[11.5px] text-text-secondary">
                {hit.text}
              </span>
            </button>
          ))}
        </div>
      ))}
    </div>
  )
}
