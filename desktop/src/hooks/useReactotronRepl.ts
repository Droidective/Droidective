import { useCallback, useEffect, useRef, useState } from "react"
import { reactotronSend } from "@/lib/daemon"
import { evaluate, listReplNames, readReplEvent } from "@/lib/reactotron-state"
import type { TimelineRow } from "@/lib/reactotron-rows"

/**
 * The REPL screen's session.
 *
 * The same shape as the State screen's, for the same reason: a command goes out
 * over `/v1/reactotron/send` and its answer arrives as an ordinary row on the
 * shared timeline, so this watches the feed and picks out the two replies that
 * belong to it.
 */
export interface ReactotronReplSession {
  /** What the app registered with `Reactotron.repl(name, value)`. */
  names: string[]
  /** The last expression's answer, already formatted. */
  result: string | null
  notice: string | null

  refresh: () => void
  run: (code: string) => void
}

export function useReactotronRepl(rows: readonly TimelineRow[]): ReactotronReplSession {
  const [names, setNames] = useState<string[]>([])
  const [result, setResult] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const seen = useRef(0)

  const send = useCallback((kind: string, payload: Parameters<typeof reactotronSend>[1]) => {
    void reactotronSend(kind, payload)
      .then((sent) => {
        if (sent.delivered === 0) setNotice("No app is connected.")
        else setNotice(null)
      })
      .catch(() => {
        setNotice("The relay could not send that.")
      })
  }, [])

  useEffect(() => {
    const fresh = rows.filter((row) => row.id >= seen.current)
    if (rows.length > 0) seen.current = (rows.at(-1)?.id ?? 0) + 1
    for (const row of fresh) {
      const event = readReplEvent(row.command.type, row.command.payload)
      if (event === null) continue
      if (event.kind === "names") setNames(event.names)
      else setResult(event.text)
    }
  }, [rows])

  const refresh = useCallback(() => {
    const command = listReplNames()
    send(command.kind, command.payload)
  }, [send])

  // Asked for on open, not only on Refresh: an expression box with no list of
  // names above it is a prompt with nothing to type into.
  useEffect(() => {
    refresh()
  }, [refresh])

  return {
    names,
    result,
    notice,
    refresh,
    run: useCallback(
      (code: string) => {
        if (code.trim() === "") return
        const command = evaluate(code)
        send(command.kind, command.payload)
      },
      [send],
    ),
  }
}
