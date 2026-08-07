import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { asDaemonError, listFiles, rootStatus } from "@/lib/daemon"
import {
  currentPath,
  pruneSelection,
  selectAllToggle,
  toggleSelected,
} from "@/lib/files"
import type { DaemonError, FileEntry } from "@/lib/wire"

/** Where the browser is, what is there, and what is checked. */
export interface FileListing {
  path: string
  /** The path split for the breadcrumb — the same list `path` is built from. */
  components: string[]
  atRoot: boolean
  /** Null while a folder is still being read, so "loading" and "empty" differ. */
  entries: FileEntry[] | null
  rows: FileEntry[]
  selected: FileEntry[]
  selection: ReadonlySet<string>
  /** Whether this device gives a root shell — the Root toggle's gate. */
  rooted: boolean
  rootMode: boolean
  error: DaemonError | null

  goTo: (depth: number) => void
  open: (entry: FileEntry) => void
  up: () => void
  reload: () => Promise<void>
  refresh: () => void
  setRootMode: (on: boolean) => void
  toggle: (name: string) => void
  selectAll: () => void
}

/**
 * Browsing one device's storage.
 *
 * Split from the verbs that act on it (`useFileActions`) because they change
 * for different reasons: this is navigation and a listing, that is mutation
 * and its reporting. The seam between them is `reload`.
 */
export function useFileListing(serial: string | null): FileListing {
  const [components, setComponents] = useState<string[]>([])
  const [rootMode, setRootModeState] = useState(false)
  const [entries, setEntries] = useState<FileEntry[] | null>(null)
  const [selection, setSelection] = useState<ReadonlySet<string>>(new Set())
  const [error, setError] = useState<DaemonError | null>(null)
  const rooted = useRootProbe(serial, () => {
    setRootModeState(false)
  })

  const path = currentPath(components, rootMode)

  // A different device is a different filesystem: a path from the last one
  // means nothing here.
  useEffect(() => {
    setComponents([])
    setRootModeState(false)
  }, [serial])

  useEffect(() => {
    setSelection(new Set())
  }, [path])

  const reload = useCallback(async () => {
    if (serial === null) return
    setError(null)
    try {
      const response = await listFiles({ serial, path, asRoot: rootMode })
      // A reply for a folder already navigated away from would render the
      // wrong listing under the current breadcrumb.
      if (response.path !== path) return
      setEntries(response.entries)
      setSelection((current) => pruneSelection(current, response.entries))
    } catch (thrown) {
      setEntries([])
      setError(asDaemonError(thrown))
    }
  }, [serial, path, rootMode])

  useEffect(() => {
    setEntries(null)
    void reload()
  }, [reload])

  const rows = useMemo(() => entries ?? [], [entries])
  const selected = useMemo(
    () => rows.filter((entry) => selection.has(entry.name)),
    [rows, selection],
  )

  return {
    path,
    components,
    atRoot: components.length === 0,
    entries,
    rows,
    selected,
    selection,
    rooted,
    rootMode,
    error,

    goTo: useCallback((depth: number) => {
      setComponents((current) => current.slice(0, depth))
    }, []),
    open: useCallback((entry: FileEntry) => {
      if (entry.isDir) setComponents((current) => [...current, entry.name])
    }, []),
    up: useCallback(() => {
      setComponents((current) => current.slice(0, -1))
    }, []),
    reload,
    refresh: useCallback(() => {
      void reload()
    }, [reload]),
    // Root mode is a different filesystem, so it starts at its own root.
    setRootMode: useCallback((on: boolean) => {
      setRootModeState(on)
      setComponents([])
    }, []),
    toggle: useCallback((name: string) => {
      setSelection((current) => toggleSelected(current, name))
    }, []),
    selectAll: useCallback(() => {
      setSelection((current) => selectAllToggle(current, rows))
    }, [rows]),
  }
}

/**
 * Whether `su -c id` answers uid 0 on this device.
 *
 * A probe that will not run is not worth a banner: its only consequence is
 * that the Root toggle stays hidden, which is also the right answer for every
 * device that is not rooted.
 */
function useRootProbe(serial: string | null, onUnrooted: () => void): boolean {
  const [rooted, setRooted] = useState(false)
  // Held in a ref so a caller passing an inline closure does not re-probe the
  // device on every render.
  const unrooted = useRef(onUnrooted)
  unrooted.current = onUnrooted

  useEffect(() => {
    if (serial === null) {
      setRooted(false)
      return
    }
    let live = true
    rootStatus(serial)
      .then((status) => {
        if (!live) return
        setRooted(status.hasRootShell)
        if (!status.hasRootShell) unrooted.current()
      })
      .catch(() => {
        if (live) setRooted(false)
      })
    return () => {
      live = false
    }
  }, [serial])

  return rooted
}
