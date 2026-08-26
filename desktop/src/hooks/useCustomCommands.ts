import { useCallback, useEffect, useState } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import {
  asDaemonError,
  customCommands,
  runCustomCommand,
  writeCustomCommands,
} from "@/lib/daemon"
import type { CommandPreset, CustomCommand } from "@/lib/wire"

export interface CustomCommands {
  commands: CustomCommand[]
  /** The ready-made ones to start from, as the daemon serves them. */
  presets: CommandPreset[]
  loaded: boolean
  busy: boolean
  /** Replaces the whole list — add, edit and delete all go through this. */
  save: (commands: CustomCommand[]) => Promise<void>
  run: (command: CustomCommand, serial: string, bundleId: string | null) => void
}

/**
 * The saved custom commands.
 *
 * One `save` rather than add/edit/delete, because the wire takes the whole
 * list: this side holds what it is showing, so a per-item verb would only make
 * the daemon re-derive it. The three UI verbs are list transforms, which is
 * also what makes them trivial to get right.
 */
export function useCustomCommands(): CustomCommands {
  const [commands, setCommands] = useState<CustomCommand[]>([])
  const [presets, setPresets] = useState<CommandPreset[]>([])
  const [loaded, setLoaded] = useState(false)
  const [busy, setBusy] = useState(false)
  const { show } = useNotifications()

  useEffect(() => {
    let cancelled = false
    customCommands().then(
      (answer) => {
        if (cancelled) return
        setCommands(answer.commands)
        setPresets(answer.presets)
        setLoaded(true)
      },
      (thrown: unknown) => {
        if (cancelled) return
        show({ message: asDaemonError(thrown).message, ok: false })
        setLoaded(true)
      },
    )
    return () => {
      cancelled = true
    }
    // Once, on open: the list only changes through this screen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const save = useCallback(
    async (next: CustomCommand[]) => {
      setBusy(true)
      try {
        const answer = await writeCustomCommands(next)
        // The daemon's answer, not the optimistic list: it is the one that
        // knows what actually landed on disk.
        setCommands(answer.commands)
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
      } finally {
        setBusy(false)
      }
    },
    [show],
  )

  const run = useCallback(
    (command: CustomCommand, serial: string, bundleId: string | null) => {
      setBusy(true)
      void (async () => {
        try {
          const result = await runCustomCommand(command.id, serial, bundleId)
          show({
            message: result.message,
            ok: result.ok,
            ...(result.copyText === null ? {} : { copyText: result.copyText }),
          })
        } catch (thrown) {
          show({ message: asDaemonError(thrown).message, ok: false })
        } finally {
          setBusy(false)
        }
      })()
    },
    [show],
  )

  return { commands, presets, loaded, busy, save, run }
}
