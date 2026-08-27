import {
  ChevronDown,
  ChevronRight,
  FileCode,
  Folder,
  FolderOpen,
  Hammer,
  Loader2,
  RefreshCw,
  Search,
} from "lucide-react"
import { useEffect, useMemo, useRef } from "react"

import type { Decompile } from "@/hooks/useDecompile"
import { hitsByFile, isBinary, relativePath, visibleRows } from "@/lib/decompile"
import type { DecompileFileText, DecompileHits, DecompileMode, DecompileTree } from "@/lib/wire"

/** What the two decompilers give you, in the words the Mac's screen uses. */
export const MODES: { id: DecompileMode; title: string; blurb: string }[] = [
  { id: "jadx", title: "jadx", blurb: "Java sources — readable, best for reading logic." },
  {
    id: "apktool",
    title: "apktool",
    blurb: "smali plus decoded resources and manifest — the only one you can rebuild.",
  },
]

/** The decompiled output: a tree (or search hits) beside a source viewer. */
export function DecompileBrowser({
  state,
  tree,
}: {
  state: Decompile
  tree: DecompileTree
}) {
  return (
    <div className="flex h-full min-h-0 flex-col">
      <Toolbar state={state} />
      <div className="flex min-h-0 flex-1">
        <div className="w-1/3 min-w-[180px] max-w-[420px] overflow-auto border-r border-border-subtle">
          {state.hits === null ? (
            <Tree
              tree={tree}
              expanded={state.expanded}
              selected={state.selected}
              onToggle={state.toggle}
              onOpen={state.open}
            />
          ) : (
            <Hits root={tree.root} hits={state.hits} onReveal={state.reveal} />
          )}
        </div>
        <Viewer
          root={tree.root}
          path={state.selected}
          source={state.source}
          loading={state.loadingFile}
        />
      </div>
    </div>
  )
}

function Toolbar({ state }: { state: Decompile }) {
  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle px-3 py-2">
      <select
        aria-label="Decompiler"
        value={state.mode}
        onChange={(event) => state.setMode(event.target.value as DecompileMode)}
        className="rounded border border-border-subtle bg-bg-surface px-2 py-1 text-text-primary"
      >
        {MODES.map((one) => (
          <option key={one.id} value={one.id}>
            {one.title}
          </option>
        ))}
      </select>
      <div className="relative min-w-0 flex-1">
        <Search
          size={12}
          className="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 text-text-tertiary"
        />
        <input
          value={state.query}
          placeholder="Search the decompiled sources…"
          onChange={(event) => state.setQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") state.search()
          }}
          className="w-full rounded border border-border-subtle bg-bg-surface py-1 pl-6 pr-2 text-text-primary"
        />
      </div>
      {state.searching ? <Loader2 size={13} className="animate-spin text-text-tertiary" /> : null}
      <button
        type="button"
        title="Decompile again, ignoring the cached output"
        disabled={state.busy}
        onClick={() => state.run(true)}
        className="rounded p-1 text-text-secondary hover:bg-bg-surface disabled:opacity-40"
      >
        <RefreshCw size={13} className={state.busy ? "animate-spin" : undefined} />
      </button>
      {state.mode === "apktool" ? (
        <button
          type="button"
          title="Rebuild this tree into an APK — it still has to be signed"
          disabled={state.busy}
          onClick={state.rebuild}
          className="flex items-center gap-1 rounded px-2 py-1 text-text-secondary hover:bg-bg-surface disabled:opacity-40"
        >
          <Hammer size={13} />
          Rebuild
        </button>
      ) : null}
      {/* Hidden inside APK Studio, which owns which APK is loaded — a second
          chooser here would change this tab's APK and leave the others on the
          old one. */}
      {state.embedded ? null : (
        <button
          type="button"
          onClick={state.choose}
          className="rounded border border-border-subtle px-2 py-1 text-text-secondary hover:bg-bg-surface"
        >
          Choose APK…
        </button>
      )}
    </div>
  )
}

function Tree({
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

function Hits({
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

function Viewer({
  root,
  path,
  source,
  loading,
}: {
  root: string
  path: string | null
  source: DecompileFileText | null
  loading: boolean
}) {
  const scroller = useRef<HTMLDivElement | null>(null)

  // A new file starts at the top, not wherever the last one was left.
  useEffect(() => {
    scroller.current?.scrollTo({ top: 0 })
  }, [path])

  if (path === null) {
    return (
      <div className="flex flex-1 items-center justify-center p-6 text-text-tertiary">
        Pick a file to read it.
      </div>
    )
  }
  return (
    <div className="flex min-w-0 flex-1 flex-col">
      <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle px-3 py-1.5">
        <span className="truncate text-text-secondary" title={path}>
          {relativePath(root, path)}
        </span>
        {source?.truncated === true ? (
          <span className="shrink-0 text-[11.5px] text-text-tertiary">
            first {Math.round(source.text.length / 1024)} KB of{" "}
            {Math.round(source.byteCount / 1024)} KB
          </span>
        ) : null}
      </div>
      <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
        <ViewerBody path={path} source={source} loading={loading} />
      </div>
    </div>
  )
}

function ViewerBody({
  path,
  source,
  loading,
}: {
  path: string
  source: DecompileFileText | null
  loading: boolean
}) {
  if (loading) return <p className="p-3 text-text-tertiary">Reading…</p>
  if (isBinary(path)) {
    return (
      <p className="p-3 text-text-tertiary">
        This is a binary file — apktool copies assets through as they are.
      </p>
    )
  }
  return (
    <pre className="whitespace-pre p-3 font-mono text-[11.5px] leading-[1.5] text-text-primary">
      {source?.text ?? ""}
    </pre>
  )
}
