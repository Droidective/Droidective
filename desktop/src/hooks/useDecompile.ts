import { useCallback, useEffect, useState } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import {
  asDaemonError,
  decompileApk,
  decompiledFile,
  pickFile,
  pickFolder,
  rebuildDecompiled,
  searchDecompiled,
} from "@/lib/daemon"
import { ancestors, defaultExpanded, isBinary, toggleExpanded } from "@/lib/decompile"
import type { ToastInput } from "@/lib/notifications"
import type { DecompileFileText, DecompileHits, DecompileMode, DecompileTree } from "@/lib/wire"

type Show = (input: ToastInput) => void

export interface Decompile {
  path: string | null
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
 * A failure as one line.
 *
 * Toasts carry no separate detail field, and the daemon's detail is the half
 * that says *why* — apktool's own words rather than "the tool could not
 * finish", which on its own sends nobody anywhere.
 */
function withDetail(error: { message: string; detail?: string | null }): string {
  const detail = error.detail
  if (detail === null || detail === undefined || detail === "") return error.message
  return `${error.message} ${detail}`
}

/**
 * Everything APK Decompile does, away from the markup.
 *
 * Its own hook because the pane is two screens over one piece of state — a
 * chooser and a browser — and threading eleven values plus their setters
 * between them is what makes a component too big to read.
 */
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

  const open = useCallback(
    (which: string) => {
      const root = tree?.root
      if (root === undefined) return
      setSelected(which)
      // A binary needs no read at all: the viewer says what it is instead.
      if (isBinary(which)) {
        setSource(null)
        return
      }
      setLoadingFile(true)
      void readFile(root, which, setSource, show).finally(() => setLoadingFile(false))
    },
    [tree, show],
  )

  return {
    path,
    mode,
    tree,
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
async function runDecompile(
  path: string,
  mode: DecompileMode,
  refresh: boolean,
  sink: {
    setTree: (tree: DecompileTree | null) => void
    setExpanded: (expanded: ReadonlySet<string>) => void
    show: Show
  },
): Promise<void> {
  try {
    const answer = await decompileApk(path, mode, refresh)
    sink.setTree(answer)
    sink.setExpanded(defaultExpanded(answer.tree))
  } catch (thrown) {
    sink.setTree(null)
    sink.show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

/** Pick an APK, then decompile it. A dismissed dialog is a choice, not a failure. */
async function chooseApk(
  mode: DecompileMode,
  setPath: (path: string) => void,
  start: (path: string, mode: DecompileMode, refresh: boolean) => void,
  show: Show,
): Promise<void> {
  try {
    const picked = await pickFile("APK", ["apk"])
    if (picked === null) return
    setPath(picked)
    start(picked, mode, false)
  } catch (thrown) {
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

async function readFile(
  root: string,
  path: string,
  setSource: (source: DecompileFileText | null) => void,
  show: Show,
): Promise<void> {
  try {
    setSource(await decompiledFile(root, path))
  } catch (thrown) {
    setSource(null)
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

async function runSearch(
  root: string,
  query: string,
  setHits: (hits: DecompileHits) => void,
  show: Show,
): Promise<void> {
  try {
    setHits(await searchDecompiled(root, query))
  } catch (thrown) {
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

async function runRebuild(root: string, path: string | null, show: Show): Promise<void> {
  try {
    const folder = await pickFolder()
    if (folder === null) return
    const base = (path ?? "app").split("/").pop() ?? "app"
    const name = base.replace(/\.apk$/iu, "")
    const answer = await rebuildDecompiled(root, root, `${folder}/${name}-rebuilt.apk`)
    // Unsigned by design: apktool's output will not install until it is signed,
    // and APK Sign is the screen that does that.
    show({ message: "Rebuilt. Sign it before installing.", revealPath: answer.output, ok: true })
  } catch (thrown) {
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

/** Opening the tree down to a file, so revealing a hit does not leave it hidden. */
function withAncestors(
  expanded: ReadonlySet<string>,
  root: string,
  path: string,
): Set<string> {
  const next = new Set(expanded)
  for (const directory of ancestors(root, path)) next.add(directory)
  return next
}
