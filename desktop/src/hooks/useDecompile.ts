import { useCallback, useEffect, useRef, useState } from "react"

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
  /** Why the last run failed, or null. The screen offers Try again from it. */
  failure: string | null
  /** Forget the loaded APK — the Mac's "Decompile another". */
  clearApk: () => void
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
  /**
   * What the last rebuild wrote, or null.
   *
   * Kept rather than left to the toast: the Mac's result row offers two things
   * to do with it, and a toast that has slid away cannot.
   */
  rebuilt: string | null
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

/**
 * Whether the chosen decompiler is here, and fetching it if it is not.
 *
 * The two belong together: the answer is re-asked after an install, so a
 * separate `installing` flag and a separate readiness probe would have to be
 * kept in step by their callers.
 */
function useToolInstall(mode: DecompileMode): Pick<Decompile, "toolReady" | "installing" | "install"> {
  const { show } = useNotifications()
  const [installing, setInstalling] = useState(false)
  return {
    toolReady: useToolReady(mode, installing),
    installing,
    install: () => {
      setInstalling(true)
      void fetchTool(mode, show).finally(() => setInstalling(false))
    },
  }
}

export function useDecompile(apkPath: string | null): Decompile {
  const { show } = useNotifications()

  const [path, setPath] = useState<string | null>(apkPath)
  const [failure, setFailure] = useState<string | null>(null)
  const [mode, setMode] = useState<DecompileMode>("jadx")
  const [tree, setTree] = useState<DecompileTree | null>(null)
  const [busy, setBusy] = useState(false)
  const [rebuilt, setRebuilt] = useState<string | null>(null)
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set())
  const [selected, setSelected] = useState<string | null>(null)
  const [source, setSource] = useState<DecompileFileText | null>(null)
  const [loadingFile, setLoadingFile] = useState(false)
  const { query, setQuery, hits, setHits, searching, setSearching } = useSearchState()
  const tool = useToolInstall(mode)

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
      void runDecompile(which, chosen, refresh, {
        setTree,
        setExpanded,
        setFailure,
        show,
      }).finally(() =>
        setBusy(false),
      )
    },
    [show, setHits],
  )

  const open = useOpenFile(tree, setSelected, setSource, setLoadingFile, show)
  const clearApk = useClearApk({ setPath, setTree, setFailure, setSelected, setSource })


  return {
    path,
    failure,
    clearApk,
    embedded: apkPath !== null,
    mode,
    tree,
    ...tool,
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
    rebuilt,
    rebuild: () => {
      const root = tree?.root
      if (root === undefined) return
      setBusy(true)
      void runRebuild(root, path, show)
        .then(setRebuilt)
        .finally(() => setBusy(false))
    },
  }
}

/**
 * Run the decompiler and take its tree, or clear the tree and say why.
 *
 * Clearing on failure matters: leaving the previous APK's output on screen
 * under a failure toast reads as though the new one decompiled.
 */

/**
 * Forget the loaded APK and everything read from it — "Decompile another".
 *
 * Every field together: leaving the tree or the open file behind would show
 * the previous APK's sources under a chooser asking for the next one.
 */
function useClearApk(sink: {
  setPath: (path: string | null) => void
  setTree: (tree: DecompileTree | null) => void
  setFailure: (failure: string | null) => void
  setSelected: (selected: string | null) => void
  setSource: (source: DecompileFileText | null) => void
}): () => void {
  const latest = useRef(sink)
  latest.current = sink
  return useCallback(() => {
    latest.current.setPath(null)
    latest.current.setTree(null)
    latest.current.setFailure(null)
    latest.current.setSelected(null)
    latest.current.setSource(null)
  }, [])
}

/** The in-tree search's three pieces, together so the hook stays readable. */
function useSearchState() {
  const [query, setQuery] = useState("")
  const [hits, setHits] = useState<DecompileHits | null>(null)
  const [searching, setSearching] = useState(false)
  // `useState`'s setters are stable, so the object's churn per render never
  // reaches a dependency array — the members are what callers capture.
  return { query, setQuery, hits, setHits, searching, setSearching }
}
