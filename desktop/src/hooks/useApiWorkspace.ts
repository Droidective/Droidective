import { useCallback, useEffect, useState } from "react"

import { emptyWorkspace } from "@/lib/api/defaults"
import type { ApiClientData } from "@/lib/api/model"
import { apiWorkspace, apiWrite, asDaemonError } from "@/lib/daemon"

export interface ApiWorkspaceStore {
  data: ApiClientData
  loaded: boolean
  /**
   * Set when a read or a save failed.
   *
   * Collections, environments and history live in one document; losing a
   * write silently means work disappears at the next launch with nothing
   * having said so, which is the failure the Mac's own strip exists for.
   */
  persistFailure: string | null
  retryPersist: () => void
  /** Applies an edit and writes the whole document back. */
  update: (change: (data: ApiClientData) => ApiClientData) => void
}

/**
 * The saved API Testing document.
 *
 * Its own hook because it is the half with a lifecycle: everything else in the
 * pane is a pure transform over what this holds. The whole document goes back
 * on every edit, which is what the wire takes — the same shape the deep links
 * and the custom commands use, for the same reason.
 */
export function useApiWorkspace(): ApiWorkspaceStore {
  const [data, setData] = useState<ApiClientData>(emptyWorkspace)
  const [loaded, setLoaded] = useState(false)
  const [persistFailure, setPersistFailure] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    apiWorkspace().then(
      (answer) => {
        if (cancelled) return
        setData(answer.data)
        setLoaded(true)
      },
      (thrown: unknown) => {
        if (cancelled) return
        // A workspace that will not load reads as an empty one, said out loud:
        // the pane still works, and someone can see why their collections are
        // missing rather than assuming they were lost.
        setPersistFailure(`Couldn't read your API workspace: ${asDaemonError(thrown).message}`)
        setLoaded(true)
      },
    )
    return () => {
      cancelled = true
    }
  }, [])

  const persist = useCallback((snapshot: ApiClientData) => {
    apiWrite(snapshot).then(
      () => {
        setPersistFailure(null)
      },
      (thrown: unknown) => {
        setPersistFailure(`Couldn't save your API workspace: ${asDaemonError(thrown).message}`)
      },
    )
  }, [])

  const update = useCallback(
    (change: (data: ApiClientData) => ApiClientData) => {
      setData((previous) => {
        const next = change(previous)
        persist(next)
        return next
      })
    },
    [persist],
  )

  const retryPersist = useCallback(() => {
    persist(data)
  }, [data, persist])

  return { data, loaded, persistFailure, retryPersist, update }
}
