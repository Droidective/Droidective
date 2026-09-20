import { useCallback, useEffect, useRef, useState } from "react"
import { reactotronSend } from "@/lib/daemon"
import {
  readCommandEvent,
  runCustomCommand,
  withCommand,
  withoutCommand,
  type CustomCommand,
} from "@/lib/reactotron-commands"
import type { TimelineRow } from "@/lib/reactotron-rows"

/**
 * The buttons an app registered with `Reactotron.onCustomCommand(...)`.
 *
 * Unlike State and REPL this screen asks for nothing: the client announces its
 * commands on connect and withdraws them when they go, so the list is built
 * entirely from `customCommand.register` / `.unregister` arriving on the
 * timeline. Which also means the list is empty until an app connects, and that
 * is the honest state rather than a failure.
 */
export interface ReactotronCommandsSession {
  commands: CustomCommand[]
  notice: string | null
  run: (command: CustomCommand, values: Record<string, string>) => void
}

export function useReactotronCommands(
  rows: readonly TimelineRow[],
): ReactotronCommandsSession {
  const [commands, setCommands] = useState<CustomCommand[]>([])
  const [notice, setNotice] = useState<string | null>(null)
  const seen = useRef(0)

  useEffect(() => {
    const fresh = rows.filter((row) => row.id >= seen.current)
    if (rows.length > 0) seen.current = (rows.at(-1)?.id ?? 0) + 1
    for (const row of fresh) {
      const event = readCommandEvent(row.command.type, row.command.payload)
      if (event === null) continue
      if (event.kind === "register") {
        setCommands((current) => withCommand(current, event.command))
      } else {
        setCommands((current) => withoutCommand(current, event.id))
      }
    }
  }, [rows])

  return {
    commands,
    notice,
    run: useCallback((command: CustomCommand, values: Record<string, string>) => {
      const outgoing = runCustomCommand(command, values)
      void reactotronSend(outgoing.kind, outgoing.payload)
        .then((sent) => {
          setNotice(sent.delivered === 0 ? "No app is connected." : `Sent “${command.command}”`)
        })
        .catch(() => {
          setNotice("The relay could not send that.")
        })
    }, []),
  }
}
