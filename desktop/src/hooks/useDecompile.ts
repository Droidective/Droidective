import { useCallback, useEffect, useState } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import { managedTools } from "@/lib/daemon"
import { isBinary, toggleExpanded } from "@/lib/decompile"
import {
  chooseApk,
  fetchTool,
  readFile,
  runDecompile,
  runRebuild,
  runSearch,
  withAncestors,
  type Show,
} from "@/lib/decompile-actions"
import type { DecompileFileText, DecompileHits, DecompileMode, DecompileTree } from "@/lib/wire"

export interface Decompile {
  path: string | null
  /** True when APK Studio handed the APK over and owns the choice. */
  embedded: boolean
  /** Whether the chosen decompiler is downloaded. Null until asked. */
  toolReady: boolean | null
  /** True while fetching it. */
  installing: boolean
  install: () => void
  mode: DecompileMode
  tree: DecompileTree | null
  busy: boolean
  expanded: ReadonlySet<string>
  selected: string | null
  source: DecompileFileText | null
  loadingFile: boolean
  query: string
  hits: DecompileHits | null
  searching: boolean

  setMode: (mode: DecompileMode) => void
  setQuery: (query: string) => void
  choose: () => void
  run: (refresh: boolean) => void
  toggle: (path: string) => void
  open: (path: string) => void
  search: () => void
  reveal: (path: string) => void
  rebuild: () => void
}

/**
 * Whether the chosen decompiler is downloaded.
 *
 * Asked up front rather than discovered by a failed run. jadx is a download,
 * and the old behaviour was a decompile that failed with "a tool this needs is
 * not installed" and nothing to click — a dead end on any machine that had not
 * already fetched it, which is every fresh one.
 *
 * Null means *unknown*, not missing: the daemon being unreachable is a
 * different problem, and one the rest of the screen already reports.
 */
function useToolReady(mode: DecompileMode, installing: boolean): boolean | null {
  const [ready, setReady] = useState<boolean | null>(null)
  useEffect(() => {
    let cancelled = false
    void managedTools()
      .then((tools) => {
        if (!cancelled) setReady(mode === "jadx" ? tools.jadx : tools.apktool)
      })
      .catch(() => {
        if (!cancelled) setReady(null)
      })
    return () => {
      cancelled = true
    }
  }, [mode, installing])
  return ready
}

/**
 * Opening one decompiled file.
 *
 * A binary needs no read at all — the viewer says what it is instead, rather
 * than showing a screen of replacement characters.
 */
function useOpenFile(
  tree: DecompileTree | null,
  setSelected: (path: string) => void,
  setSource: (source: DecompileFileText | null) => void,
  setLoadingFile: (loading: boolean) => void,
  show: Show,
): (path: string) => void {
  return useCallback(
    (which: string) => {
      const root = tree?.root
      if (root === undefined) return
      setSelected(which)
      if (isBinary(which)) {
        setSource(null)
        return
      }
      setLoadingFile(true)
      void readFile(root, which, setSource, show).finally(() => setLoadingFile(false))
    },
    [tree, show, setSelected, setSource, setLoadingFile],
  )
}

export function useDecompile(apkPath: string | null): Decompile {
  const { show } = useNotifications()

  const [path, setPath] = useState<string | null>(apkPath)
  const [mode, setMode] = useState<DecompileMode>("jadx")
  const [tree, setTree] = useState<DecompileTree | null>(null)
  const [busy, setBusy] = useState(false)
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set())
  const [selected, setSelected] = useState<string | null>(null)
  const [source, setSource] = useState<DecompileFileText | null>(null)
  const [loadingFile, setLoadingFile] = useState(false)
  const [query, setQuery] = useState("")
  const [hits, setHits] = useState<DecompileHits | null>(null)
  const [searching, setSearching] = useState(false)
  const [installing, setInstalling] = useState(false)
  const toolReady = useToolReady(mode, installing)

  // An APK handed in (APK Studio) should not need choosing a second time.
  useEffect(() => {
    if (apkPath !== null) setPath(apkPath)
  }, [apkPath])

  const start = useCallback(
    (which: string, chosen: DecompileMode, refresh: boolean) => {
      setHits(null)
      setSelected(null)
      setSource(null)
      setBusy(true)
      void runDecompile(which, chosen, refresh, { setTree, setExpanded, show }).finally(() =>
        setBusy(false),
      )
    },
    [show],
  )

  const open = useOpenFile(tree, setSelected, setSource, setLoadingFile, show)

  return {
    path,
    embedded: apkPath !== null,
    mode,
    tree,
    toolReady,
    installing,
    install: () => {
      setInstalling(true)
      void fetchTool(mode, show).finally(() => setInstalling(false))
    },
    busy,
    expanded,
    selected,
    source,
    loadingFile,
    query,
    hits,
    searching,
    setQuery,
    open,
    toggle: (which) => setExpanded((current) => toggleExpanded(current, which)),
    setMode: (next) => {
      setMode(next)
      // Only re-run when there is already output on screen: changing the mode
      // on the chooser is a choice, not a command.
      if (path !== null && tree !== null) start(path, next, false)
    },
    choose: () => {
      void chooseApk(mode, setPath, start, show)
    },
    run: (refresh) => {
      if (path !== null) start(path, mode, refresh)
    },
    search: () => {
      const root = tree?.root
      if (root === undefined || query.trim() === "") return
      setSearching(true)
      void runSearch(root, query.trim(), setHits, show).finally(() => setSearching(false))
    },
    reveal: (which) => {
      const root = tree?.root
      if (root === undefined) return
      setExpanded((current) => withAncestors(current, root, which))
      setHits(null)
      open(which)
    },
    rebuild: () => {
      const root = tree?.root
      if (root === undefined) return
      setBusy(true)
      void runRebuild(root, path, show).finally(() => setBusy(false))
    },
  }
}

/**
 * Run the decompiler and take its tree, or clear the tree and say why.
 *
 * Clearing on failure matters: leaving the previous APK's output on screen
 * under a failure toast reads as though the new one decompiled.
 */
