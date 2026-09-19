import { useCallback, useEffect, useState } from "react"
import { asDaemonError, expandSnippet, snippets as readSnippets, writeSnippet } from "@/lib/daemon"
import { recent, type Snippet } from "@/lib/snippets"
import type { DaemonError } from "@/lib/wire"

export interface Snippets {
  all: Snippet[]
  /** Most recently used first — the quick-insert order. */
  ranked: Snippet[]
  error: DaemonError | null
  reload: () => void
  add: (name: string, text: string) => Promise<boolean>
  remove: (name: string) => Promise<void>
  /**
   * The snippet's text with its live values filled in, recording the use.
   *
   * One call rather than two: a snippet is inserted and counted in the same
   * gesture, and doing the second afterwards is how a ranking drifts from what
   * somebody actually pressed.
   */
  insert: (snippet: Snippet) => Promise<string>
}

/** The saved Send Text snippets, shared by the screen and the panel. */
export function useSnippets(): Snippets {
  const [all, setAll] = useState<Snippet[]>([])
  const [error, setError] = useState<DaemonError | null>(null)

  const reload = useCallback(() => {
    void readSnippets()
      .then((list) => {
        setAll(list)
        setError(null)
      })
      .catch((thrown: unknown) => {
        setError(asDaemonError(thrown))
      })
  }, [])

  useEffect(reload, [reload])

  return {
    all,
    ranked: recent(all),
    error,
    reload,
    add: useCallback(async (name: string, text: string) => {
      try {
        setAll(await writeSnippet({ op: "add", name, text }))
        setError(null)
        return true
      } catch (thrown) {
        // The daemon refuses an empty name, empty text or a duplicate with a
        // 409 carrying the reason — which is the message worth showing.
        setError(asDaemonError(thrown))
        return false
      }
    }, []),
    remove: useCallback(async (name: string) => {
      try {
        setAll(await writeSnippet({ op: "remove", name }))
      } catch (thrown) {
        setError(asDaemonError(thrown))
      }
    }, []),
    insert: useCallback(async (snippet: Snippet) => {
      const expanded = await expandSnippet(snippet.text)
      // Best-effort: the ranking is bookkeeping, and a snippet removed in
      // another window must not turn an insert into a failure.
      void writeSnippet({ op: "use", name: snippet.name })
        .then(setAll)
        .catch(() => {})
      return expanded.text
    }, []),
  }
}
