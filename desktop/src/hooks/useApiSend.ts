import { useCallback, useRef, useState } from "react"

import { newId } from "@/lib/api/defaults"
import { addToHistory, historyEntry } from "@/lib/api/history"
import type { ApiClientData, AuthSpec, SavedRequest } from "@/lib/api/model"
import type { VariableScope } from "@/lib/api/variables"
import { apiCancel, apiSend, asDaemonError, type ApiSendResponse } from "@/lib/daemon"

/** A rejection with nowhere useful to go. Named so the intent is not "oops". */
const ignore = () => {}

export interface ApiSender {
  response: ApiSendResponse | null
  errorText: string | null
  warnings: string[]
  sending: boolean
  send: (request: SavedRequest, scope: VariableScope, inherited: AuthSpec | null) => void
  cancel: () => void
  /** Clears the pane, for a request being opened in place of this one. */
  reset: () => void
}

/**
 * One send at a time, with a real Cancel.
 *
 * Cancel goes to the daemon rather than only dropping the answer here: the
 * Mac's button tears the URLSession task down, and one that let a
 * sixty-second request run on behind a pane that had moved on would be a
 * different button wearing the same label.
 *
 * The in-flight handle is a ref, not state — nothing renders from it, and it
 * has to be readable by the `finally` of a send that is already running.
 */
export function useApiSend(
  update: (change: (data: ApiClientData) => ApiClientData) => void,
): ApiSender {
  const [response, setResponse] = useState<ApiSendResponse | null>(null)
  const [errorText, setErrorText] = useState<string | null>(null)
  const [warnings, setWarnings] = useState<string[]>([])
  const [sending, setSending] = useState(false)
  const inFlight = useRef<string | null>(null)

  const cancel = useCallback(() => {
    const handle = inFlight.current
    inFlight.current = null
    setSending(false)
    if (handle === null) return
    // Fire and forget: a cancel that arrives after the send finished is the
    // ordinary race, and `cancelled: false` is not worth reporting.
    void apiCancel(handle).catch(ignore)
  }, [])

  const reset = useCallback(() => {
    cancel()
    setResponse(null)
    setErrorText(null)
    setWarnings([])
  }, [cancel])

  const send = useCallback(
    (request: SavedRequest, scope: VariableScope, inherited: AuthSpec | null) => {
      if (request.url.trim() === "") return
      const handle = newId()
      inFlight.current = handle
      setSending(true)
      setErrorText(null)
      setResponse(null)
      setWarnings([])

      void (async () => {
        try {
          const answer = await apiSend({
            request,
            scope,
            inheritedAuth: inherited,
            sendId: handle,
          })
          // A send that was cancelled has already been replaced; writing its
          // answer would put a response under a request nobody is looking at.
          if (inFlight.current !== handle) return
          setResponse(answer)
          setWarnings(answer.warnings)
          update((previous) => addToHistory(previous, succeeded(request, answer)))
        } catch (thrown) {
          if (inFlight.current !== handle) return
          const failure = asDaemonError(thrown)
          setErrorText(failure.message)
          update((previous) =>
            addToHistory(
              previous,
              historyEntry(request, { url: request.url, errorText: failure.message }),
            ),
          )
        } finally {
          if (inFlight.current === handle) {
            inFlight.current = null
            setSending(false)
          }
        }
      })()
    },
    [update],
  )

  return { response, errorText, warnings, sending, send, cancel, reset }
}

/** History records the URL that actually went out, not the one that was typed. */
function succeeded(request: SavedRequest, answer: ApiSendResponse) {
  return historyEntry(request, {
    url: answer.preparedURL === "" ? request.url : answer.preparedURL,
    statusCode: answer.statusCode,
    elapsedMs: answer.elapsedMs,
    responseSize: answer.size,
  })
}
