import { useCallback, useEffect, useMemo, useState } from "react"

import type { ConsoleRow } from "@/lib/console-feed"
import { countLabel, currentMatch, findMatches, nextIndex, prevIndex } from "@/lib/console-find"
import { isMenuOwned } from "@/lib/menuKeys"
import { hasModifier } from "@/lib/platform"

export interface ConsoleFind {
  open: boolean
  /** The toolbar button's action — the same thing Ctrl+F does. */
  openBar: () => void
  query: string
  setQuery: (query: string) => void
  /** The id of the row the arrows are on, for the feed to mark and scroll to. */
  current: number | null
  count: string
  hasMatches: boolean
  next: () => void
  prev: () => void
  close: () => void
}

/**
 * Find-in-console, and the key that opens it.
 *
 * `Ctrl+F` where the Mac binds `⌘F` — the standing shortcut exception. Bound
 * only while this tab is the one on screen, for the Mac's reason: every open
 * tab stays mounted, so a hidden console would otherwise win the key and open
 * a find bar nobody can see.
 */
export function useConsoleFind(rows: readonly ConsoleRow[], active: boolean): ConsoleFind {
  const [open, setOpen] = useState(false)
  const [query, setQueryState] = useState("")
  const [index, setIndex] = useState(0)

  const matches = useMemo(() => findMatches(rows, query), [rows, query])

  const setQuery = useCallback((next: string) => {
    setQueryState(next)
    // Back to the first match on every keystroke: the matches are a different
    // set now, and keeping the old position would land on an unrelated row.
    setIndex(0)
  }, [])

  const close = useCallback(() => {
    setOpen(false)
    setQueryState("")
    setIndex(0)
  }, [])

  useEffect(() => {
    if (!active) return
    const onKeyDown = (event: KeyboardEvent) => {
      // The native menu gets its own keys first; answering one here too would
      // run it twice. Ctrl+F is not among them, but the guard is what keeps
      // that true if one is added.
      if (isMenuOwned(event)) return
      if (!hasModifier(event) || event.altKey || event.shiftKey) return
      if (event.key !== "f") return
      event.preventDefault()
      setOpen(true)
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [active])

  return {
    open,
    openBar: () => {
      setOpen(true)
    },
    query,
    setQuery,
    current: currentMatch(matches, index),
    count: countLabel(query, matches, index),
    hasMatches: matches.length > 0,
    next: () => {
      setIndex((at) => nextIndex(at, matches.length))
    },
    prev: () => {
      setIndex((at) => prevIndex(at, matches.length))
    },
    close,
  }
}
