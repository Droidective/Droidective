import { ExternalLink, Hammer, Loader2, RefreshCw, Search } from "lucide-react"
import { useEffect, useRef, useState } from "react"

import type { Decompile } from "@/hooks/useDecompile"
import { DecompileTreeView as Tree, Hits } from "@/components/DecompileTreeView"
import { DecompileViewerBody as ViewerBody } from "@/components/DecompileViewerBody"
import { revealPath } from "@/lib/daemon"
import { relativePath } from "@/lib/decompile"
import { hasModifier } from "@/lib/platform"
import type { DecompileFileText, DecompileMode, DecompileTree } from "@/lib/wire"

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
          // The Mac's verb once a tree is on screen: this drops the loaded APK
          // and goes back to the chooser, where "Choose another APK" is what
          // the failure state offers.
          onClick={state.clearApk}
          className="rounded border border-border-subtle px-2 py-1 text-text-secondary hover:bg-bg-surface"
        >
          Decompile another
        </button>
      )}
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

  const [find, setFind] = useState("")
  const findField = useRef<HTMLInputElement | null>(null)

  // A new file starts at the top, not wherever the last one was left. The
  // query goes with it: a find left over from another file would mark rows
  // nobody searched for.
  useEffect(() => {
    scroller.current?.scrollTo({ top: 0 })
    setFind("")
  }, [path])

  // Ctrl+F focuses the box rather than opening a second one — there is only
  // ever one file on screen here.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!hasModifier(event) || event.altKey || event.shiftKey || event.key !== "f") return
      event.preventDefault()
      findField.current?.focus()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [])

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
        <div className="ml-auto flex shrink-0 items-center gap-1">
          <input
            value={find}
            placeholder="Find"
            aria-label="Find in file"
            // Ctrl+F where the Mac binds ⌘F — the standing shortcut exception.
            title="Find in file (Ctrl+F)"
            ref={findField}
            onChange={(event) => {
              setFind(event.target.value)
            }}
            onKeyDown={(event) => {
              if (event.key === "Escape") setFind("")
            }}
            className="w-32 rounded border border-border-subtle bg-bg-surface px-2 py-0.5 text-text-primary"
          />
          {/* The Mac's verb. A decompiled file is often wanted in a real
              editor, and this is the only way out of the viewer to one. */}
          <button
            type="button"
            title="Open externally"
            aria-label="Open externally"
            onClick={() => void revealPath(path)}
            className="rounded p-1 text-text-secondary hover:bg-bg-surface"
          >
            <ExternalLink size={13} />
          </button>
        </div>
      </div>
      <div ref={scroller} className="min-h-0 flex-1 overflow-auto">
        <ViewerBody path={path} source={source} loading={loading} find={find} />
      </div>
    </div>
  )
}
