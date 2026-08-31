import { useCallback, useMemo, useState } from "react"

import { useApiSend } from "@/hooks/useApiSend"
import { useApiWorkspace, type ApiWorkspaceStore } from "@/hooks/useApiWorkspace"
import { newRequest } from "@/lib/api/defaults"
import type { AuthSpec, SavedRequest } from "@/lib/api/model"
import { scopeFor, unresolvedInRequest, type VariableScope } from "@/lib/api/variables"
import { collectionFor, hasUnsavedChanges, inheritedAuth } from "@/lib/api/workspace"
import type { ApiSendResponse } from "@/lib/daemon"

export interface ApiClient extends ApiWorkspaceStore {
  current: SavedRequest
  setCurrent: (change: (request: SavedRequest) => SavedRequest) => void
  currentCollectionId: string | null
  setCurrentCollectionId: (id: string | null) => void
  open: (request: SavedRequest, collectionId: string | null) => void
  startNewRequest: () => void
  hasUnsaved: boolean

  scope: VariableScope
  inherited: AuthSpec | null
  unresolved: string[]

  response: ApiSendResponse | null
  errorText: string | null
  warnings: string[]
  sending: boolean
  canSend: boolean
  send: () => void
  cancelSend: () => void
}

/**
 * State and actions behind the API Testing pane — the Mac's `ApiClientModel`.
 *
 * Two hooks under it, split by lifecycle: `useApiWorkspace` owns the saved
 * document, `useApiSend` owns the one request in flight. What is left here is
 * the *open* request and the scope it resolves in, which is the part that
 * depends on both.
 */
export function useApiClient(): ApiClient {
  const workspace = useApiWorkspace()
  const sender = useApiSend(workspace.update)

  const [current, setCurrentState] = useState<SavedRequest>(newRequest)
  const [currentCollectionId, setCurrentCollectionId] = useState<string | null>(null)

  const { data } = workspace
  const collection = useMemo(
    () => collectionFor(data, currentCollectionId),
    [data, currentCollectionId],
  )
  const scope = useMemo(() => scopeFor(data, collection), [data, collection])
  const inherited = useMemo(() => inheritedAuth(collection), [collection])
  const unresolved = useMemo(() => unresolvedInRequest(current, scope), [current, scope])
  const hasUnsaved = useMemo(
    () => hasUnsavedChanges(data, current, currentCollectionId),
    [data, current, currentCollectionId],
  )

  const { reset } = sender
  const open = useCallback(
    (request: SavedRequest, collectionId: string | null) => {
      reset()
      setCurrentState(request)
      setCurrentCollectionId(collectionId)
    },
    [reset],
  )

  const startNewRequest = useCallback(() => {
    open(newRequest(), currentCollectionId)
  }, [open, currentCollectionId])

  const setCurrent = useCallback((change: (request: SavedRequest) => SavedRequest) => {
    setCurrentState(change)
  }, [])

  const { send: performSend } = sender
  const send = useCallback(() => {
    performSend(current, scope, inherited)
  }, [performSend, current, scope, inherited])

  return {
    ...workspace,
    current,
    setCurrent,
    currentCollectionId,
    setCurrentCollectionId,
    open,
    startNewRequest,
    hasUnsaved,
    scope,
    inherited,
    unresolved,
    response: sender.response,
    errorText: sender.errorText,
    warnings: sender.warnings,
    sending: sender.sending,
    canSend: current.url.trim() !== "" && !sender.sending,
    send,
    cancelSend: sender.cancel,
  }
}
