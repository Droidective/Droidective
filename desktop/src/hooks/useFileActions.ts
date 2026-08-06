import { useCallback, useState } from "react"
import { asDaemonError, fileOperation, pullFile } from "@/lib/daemon"
import {
  batchLabel,
  childPath,
  folderNameToCreate,
  leafName,
  pasteOperation,
  runInOrder,
  summariseBatch,
  type FileClipboard,
} from "@/lib/files"
import type { FileEntry, FileOperation } from "@/lib/wire"

/** What an operation reported, and where it left something if it did. */
export interface FileNotice {
  ok: boolean
  message: string
  detail?: string
  /** A host path, for a Show in folder button. */
  path?: string
}

export interface FileActions {
  clipboard: FileClipboard | null
  /** What is running, as a gerund for the banner: "Deleting". */
  busy: string | null
  notice: FileNotice | null

  remember: (targets: FileEntry[], isCut: boolean) => void
  forget: () => void
  paste: () => void
  pull: (targets: FileEntry[]) => void
  remove: (targets: FileEntry[]) => void
  createFolder: (raw: string) => void
  dismissNotice: () => void
}

/**
 * The verbs that write to a device, and what they report.
 *
 * Paths go over exactly as `ls` gave them back. Nothing here escapes one:
 * device-shell quoting happens once, in ADBKit's `FileExplorerService`, and a
 * path escaped on the way out would be quoted twice and address the wrong file.
 */
export function useFileActions({
  serial,
  path,
  rootMode,
  reload,
}: {
  serial: string | null
  path: string
  rootMode: boolean
  reload: () => Promise<void>
}): FileActions {
  const [clipboard, setClipboard] = useState<FileClipboard | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [notice, setNotice] = useState<FileNotice | null>(null)

  const operate = useCallback(
    (op: FileOperation, target: string, destination?: string) => () => {
      if (serial === null) return Promise.resolve({ ok: false, message: "No device." })
      return fileOperation(
        destination === undefined
          ? { serial, op, path: target, asRoot: rootMode }
          : { serial, op, path: target, destination, asRoot: rootMode },
      )
    },
    [serial, rootMode],
  )

  /** Runs a batch, stopping at the first refusal, then reloads the folder. */
  const run = useCallback(
    (label: string, succeeded: string, calls: (() => Promise<{ ok: boolean; message: string }>)[]) => {
      setBusy(label)
      setNotice(null)
      void (async () => {
        try {
          setNotice(summariseBatch(await runInOrder(calls), succeeded))
        } catch (thrown) {
          setNotice(failed(thrown))
        } finally {
          setBusy(null)
          await reload()
        }
      })()
    },
    [reload],
  )

  const paths = useCallback(
    (targets: FileEntry[]) => targets.map((entry) => childPath(path, entry.name)),
    [path],
  )

  return {
    clipboard,
    busy,
    notice,

    remember: useCallback(
      (targets: FileEntry[], isCut: boolean) => {
        setClipboard({ paths: paths(targets), isCut })
      },
      [paths],
    ),
    forget: useCallback(() => {
      setClipboard(null)
    }, []),

    paste: usePaste({ clipboard, setClipboard, operate, path, run }),
    pull: usePull({ serial, rootMode, paths, setBusy, setNotice }),

    remove: useCallback(
      (targets: FileEntry[]) => {
        const names = targets.map((entry) => entry.name)
        run(
          "Deleting",
          `Deleted ${batchLabel(names)}`,
          paths(targets).map((target) => operate("delete", target)),
        )
      },
      [operate, paths, run],
    ),

    createFolder: useCallback(
      (raw: string) => {
        const name = folderNameToCreate(raw)
        if (name === null) return
        run("Creating", `Created ${name}`, [operate("makeDirectory", childPath(path, name))])
      },
      [operate, path, run],
    ),

    dismissNotice: useCallback(() => {
      setNotice(null)
    }, []),
  }
}

/**
 * Paste empties the clipboard first.
 *
 * A move that leaves its sources on the clipboard offers a second paste of
 * paths that are no longer there — which is a confusing failure rather than
 * a useful one.
 */
function usePaste({
  clipboard,
  setClipboard,
  operate,
  path,
  run,
}: {
  clipboard: FileClipboard | null
  setClipboard: (value: FileClipboard | null) => void
  operate: (
    op: FileOperation,
    target: string,
    destination?: string,
  ) => () => Promise<{ ok: boolean; message: string }>
  path: string
  run: (
    label: string,
    succeeded: string,
    calls: (() => Promise<{ ok: boolean; message: string }>)[],
  ) => void
}): () => void {
  return useCallback(() => {
    if (clipboard === null) return
    const op = pasteOperation(clipboard)
    const names = clipboard.paths.map(leafName)
    const sources = clipboard.paths
    setClipboard(null)
    run(
      op === "move" ? "Moving" : "Copying",
      `${op === "move" ? "Moved" : "Copied"} ${batchLabel(names)}`,
      sources.map((source) => operate(op, source, path)),
    )
  }, [clipboard, operate, path, run, setClipboard])
}

/**
 * Pulling is not a `run` batch: it answers with a host path rather than a
 * device result, and it changes nothing on the device, so there is nothing to
 * reload afterwards.
 */
function usePull({
  serial,
  rootMode,
  paths,
  setBusy,
  setNotice,
}: {
  serial: string | null
  rootMode: boolean
  paths: (targets: FileEntry[]) => string[]
  setBusy: (value: string | null) => void
  setNotice: (value: FileNotice | null) => void
}): (targets: FileEntry[]) => void {
  return useCallback(
    (targets: FileEntry[]) => {
      if (serial === null || targets.length === 0) return
      const names = targets.map((entry) => entry.name)
      const sources = paths(targets)
      setBusy("Pulling")
      setNotice(null)
      void (async () => {
        try {
          let landed: string | null = null
          for (const source of sources) {
            landed = (await pullFile({ serial, path: source, asRoot: rootMode })).path
          }
          setNotice({
            ok: true,
            message: `Pulled ${batchLabel(names)}`,
            ...(landed === null ? {} : { path: landed }),
          })
        } catch (thrown) {
          setNotice(failed(thrown))
        } finally {
          setBusy(null)
        }
      })()
    },
    [paths, rootMode, serial, setBusy, setNotice],
  )
}

/** A thrown failure as a notice, so there is one place a result is reported. */
function failed(thrown: unknown): FileNotice {
  const error = asDaemonError(thrown)
  return {
    ok: false,
    message: error.message,
    ...(error.detail === null ? {} : { detail: error.detail }),
  }
}
