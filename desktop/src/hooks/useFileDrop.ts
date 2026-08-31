import { useCallback, useEffect, useRef, useState } from "react"

import { useNotifications } from "@/hooks/useNotifications"
import {
  asDaemonError,
  discardDroppedFile,
  fileOperation,
  installPath,
  stageDroppedFile,
} from "@/lib/daemon"
import { classifyDrop, droppedLabel, type DropContext } from "@/lib/file-drop"

/** A rejection with nowhere useful to go. Named so the intent is not "oops". */
const ignore = () => {}

export interface FileDrop {
  /** True while a file drag is over the window, for the overlay. */
  over: boolean
  /** True while the drop is being staged and acted on. */
  busy: boolean
}

/**
 * Files dropped on the window from the file manager.
 *
 * The bytes are staged rather than the path being read, and that is forced
 * rather than chosen: Tauri's own drop handler hands over paths, but turning it
 * on stops every HTML5 drag in the page working — the tab strip, the sidebar
 * and the mirror wall. That was checked rather than assumed. So the handler
 * stays off, the page gets an ordinary web `drop`, and the file is written once
 * to a temp directory on the way through.
 *
 * The listener is on the window — it has to be, or a file dropped on the
 * sidebar would land nowhere — and the two kinds of drag are told apart by
 * what the drag carries: an in-app tab or row drag has only `text/plain`, so
 * everything here is skipped for it. The reverse guard is on the reorder
 * targets, which ignore a drag carrying files (`carriesFiles` in `dnd.ts`) —
 * an empty `text/plain` reads back as a valid index otherwise.
 */
export function useFileDrop(context: DropContext): FileDrop {
  const [over, setOver] = useState(false)
  const [busy, setBusy] = useState(false)
  const { show } = useNotifications()

  // The context changes on every selection; the listener should not be torn
  // down and rebuilt for that, so it reads the latest through a ref.
  const latest = useRef(context)
  latest.current = context

  const act = useCallback(
    async (files: File[]) => {
      setBusy(true)
      const staged: string[] = []
      try {
        for (const file of files) {
          staged.push(await stageDroppedFile(file))
        }
        const action = classifyDrop(staged, latest.current)
        if (action.kind === "ignore") {
          show({ message: action.reason, ok: false })
          return
        }
        await run(action, latest.current)
        show({
          message:
            action.kind === "install"
              ? `Installed ${droppedLabel(action.paths)}`
              : `Pushed ${droppedLabel(action.paths)} to ${action.destination}`,
          ok: true,
          important: true,
        })
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
      } finally {
        for (const path of staged) void discardDroppedFile(path).catch(ignore)
        setBusy(false)
      }
    },
    [show],
  )

  useEffect(() => {
    // `types` rather than `files`: during a drag the file list is empty for
    // security, and "Files" is the only signal that one is coming.
    const carriesFiles = (event: DragEvent) =>
      event.dataTransfer?.types.includes("Files") === true

    const onOver = (event: DragEvent) => {
      if (!carriesFiles(event)) return
      event.preventDefault()
      setOver(true)
    }
    const onLeave = (event: DragEvent) => {
      // `relatedTarget` is null when the pointer has left the window rather
      // than moved between two elements inside it.
      if (event.relatedTarget === null) setOver(false)
    }
    const onDrop = (event: DragEvent) => {
      setOver(false)
      if (!carriesFiles(event)) return
      event.preventDefault()
      const files = [...(event.dataTransfer?.files ?? [])]
      if (files.length > 0) void act(files)
    }

    globalThis.addEventListener("dragover", onOver)
    globalThis.addEventListener("dragleave", onLeave)
    globalThis.addEventListener("drop", onDrop)
    return () => {
      globalThis.removeEventListener("dragover", onOver)
      globalThis.removeEventListener("dragleave", onLeave)
      globalThis.removeEventListener("drop", onDrop)
    }
  }, [act])

  return { over, busy }
}

/** Install or push, once the drop has been classified. */
async function run(
  action: Exclude<ReturnType<typeof classifyDrop>, { kind: "ignore" }>,
  context: DropContext,
): Promise<void> {
  if (action.kind === "install") {
    await installPath(context.serials, action.paths[0] ?? "")
    return
  }
  // `push` is one of the filesystem route's operations rather than a route of
  // its own — the daemon owns the list of what may be done to a device's
  // filesystem, and a second route would be a second place for it to drift.
  for (const path of action.paths) {
    await fileOperation({
      serial: context.serials[0] ?? "",
      op: "push",
      path,
      destination: action.destination,
      asRoot: false,
    })
  }
}
