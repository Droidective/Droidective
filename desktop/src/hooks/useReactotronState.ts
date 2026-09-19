import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type Dispatch,
  type MutableRefObject,
  type SetStateAction,
} from "react"
import { reactotronSend } from "@/lib/daemon"
import type { JsonValue } from "@/lib/json"
import {
  applyChanges,
  dispatchAction,
  loadStateTree,
  parseAction,
  readStateEvent,
  restoreSnapshot,
  subscribeTo,
  takeSnapshot,
  withoutWatch,
  withWatch,
  type Outgoing,
  type Snapshot,
  type Watch,
} from "@/lib/reactotron-state"
import type { TimelineRow } from "@/lib/reactotron-rows"

/**
 * The State screen's session: what has been asked for, and what came back.
 *
 * The protocol carries no correlation id — a request is answered by a separate
 * command on the shared timeline — so this watches the same rows the feed
 * renders and picks out the replies. `pendingSnapshot` is the one piece of
 * state that disambiguates: a `state.backup.response` is the tree when the tree
 * was asked for and a snapshot when Take Snapshot was pressed, and only the
 * asker knows which.
 */
export interface ReactotronStateSession {
  tree: JsonValue | null
  /** A request is out and nothing has answered yet. */
  loadingTree: boolean
  watches: Watch[]
  snapshots: Snapshot[]
  /** The last thing that went wrong, for a line under the card. */
  notice: string | null

  loadTree: () => void
  addWatch: (raw: string) => void
  removeWatch: (path: string) => void
  dispatch: (text: string) => void
  snapshot: () => void
  restore: (snapshot: Snapshot) => void
  deleteSnapshot: (id: string) => void
}

/**
 * How long to wait for a store plugin before saying there is not one.
 *
 * An app with no `reactotron-redux` or `reactotron-mst` simply never answers,
 * and a spinner that runs forever is the worst reading of that — the Mac waits
 * the same four seconds and then says so.
 */
const answerWindow = 4000

export function useReactotronState(rows: readonly TimelineRow[]): ReactotronStateSession {
  const [tree, setTree] = useState<JsonValue | null>(null)
  const [loadingTree, setLoadingTree] = useState(false)
  const [watches, setWatches] = useState<Watch[]>([])
  const [snapshots, setSnapshots] = useState<Snapshot[]>([])
  const [notice, setNotice] = useState<string | null>(null)

  /** Take Snapshot is waiting for the next backup, rather than the tree load. */
  const pendingSnapshot = useRef(false)

  const send = useCallback((commands: Outgoing | Outgoing[]) => {
    for (const command of Array.isArray(commands) ? commands : [commands]) {
      void reactotronSend(command.kind, command.payload).then((result) => {
        if (result.delivered === 0) setNotice("No app is connected.")
      }).catch(() => {
        setNotice("The relay could not send that.")
      })
    }
  }, [])

  useStateReplies(rows, {
    onTree: (state) => {
      setTree(state)
      setLoadingTree(false)
    },
    onBackup: (state, at, id) => {
      if (pendingSnapshot.current) {
        pendingSnapshot.current = false
        setSnapshots((current) => [{ id, takenAt: at, state }, ...current])
        return
      }
      setTree(state)
      setLoadingTree(false)
    },
    onChanges: (changes, at) => {
      setWatches((current) => applyChanges(current, changes, at))
    },
  })

  const loadTree = useCallback(() => {
    setNotice(null)
    setLoadingTree(true)
    send(loadStateTree())
    globalThis.setTimeout(() => {
      setLoadingTree((waiting) => {
        if (waiting) {
          setNotice(
            "No state received — wire reactotron-redux or reactotron-mst into your store to browse it here.",
          )
        }
        return false
      })
    }, answerWindow)
  }, [send])

  return {
    tree,
    loadingTree,
    watches,
    snapshots,
    notice,
    loadTree,
    ...useStateCommands({ send, setWatches, setSnapshots, setNotice, pendingSnapshot }),
  }
}

/**
 * The seven things the screen can ask the app to do.
 *
 * Split from the state itself so each stays inside the line budget, and because
 * they divide cleanly: above is what this screen *holds*, here is what it
 * *asks*. Every one of them is a send plus a local edit, and none reads the
 * state back.
 */
function useStateCommands({
  send,
  setWatches,
  setSnapshots,
  setNotice,
  pendingSnapshot,
}: {
  send: (commands: Outgoing | Outgoing[]) => void
  setWatches: Dispatch<SetStateAction<Watch[]>>
  setSnapshots: Dispatch<SetStateAction<Snapshot[]>>
  setNotice: (notice: string | null) => void
  pendingSnapshot: MutableRefObject<boolean>
}) {
  return {
    addWatch: useCallback(
      (raw: string) => {
        setWatches((current) => {
          const paths = withWatch(current.map((watch) => watch.path), raw)
          if (paths === null) return current
          send(subscribeTo(paths))
          return [...current, { path: raw.trim(), value: undefined, at: null }]
        })
      },
      [send, setWatches],
    ),

    removeWatch: useCallback(
      (path: string) => {
        setWatches((current) => {
          send(subscribeTo(withoutWatch(current.map((watch) => watch.path), path)))
          return current.filter((watch) => watch.path !== path)
        })
      },
      [send, setWatches],
    ),

    dispatch: useCallback(
      (text: string) => {
        const parsed = parseAction(text)
        if (!parsed.ok) {
          setNotice(parsed.reason)
          return
        }
        setNotice(null)
        send(dispatchAction(parsed.action))
      },
      [send, setNotice],
    ),

    snapshot: useCallback(() => {
      setNotice(null)
      pendingSnapshot.current = true
      send(takeSnapshot())
      globalThis.setTimeout(() => {
        if (!pendingSnapshot.current) return
        // Otherwise it stays pending forever and the next unrelated backup is
        // silently captured as the snapshot — the Mac's own note.
        pendingSnapshot.current = false
        setNotice(
          "No snapshot received — wire reactotron-redux or reactotron-mst into your store to snapshot it.",
        )
      }, answerWindow)
    }, [send, setNotice, pendingSnapshot]),

    restore: useCallback(
      (snapshot: Snapshot) => {
        setNotice(null)
        send(restoreSnapshot(snapshot.state))
      },
      [send, setNotice],
    ),

    deleteSnapshot: useCallback(
      (id: string) => {
        setSnapshots((current) => current.filter((snapshot) => snapshot.id !== id))
      },
      [setSnapshots],
    ),
  }
}

/**
 * Fold the replies out of the shared timeline.
 *
 * Its own hook so `useReactotronState` stays inside the line budget, and
 * because it is one idea: the protocol carries no correlation id, so every
 * answer arrives as an ordinary row and this is the only place that knows which
 * rows are answers. Rows already folded in are remembered by id — the feed
 * replaces the array on every flush, and replaying it would re-add every
 * snapshot each time.
 */
function useStateReplies(
  rows: readonly TimelineRow[],
  handlers: {
    onTree: (state: JsonValue) => void
    onBackup: (state: JsonValue, at: number, id: string) => void
    onChanges: (changes: { path: string; value: JsonValue }[], at: number) => void
  },
) {
  const seen = useRef(0)
  const latest = useRef(handlers)
  latest.current = handlers

  useEffect(() => {
    const fresh = rows.filter((row) => row.id >= seen.current)
    if (rows.length > 0) seen.current = (rows.at(-1)?.id ?? 0) + 1
    for (const row of fresh) {
      const event = readStateEvent(row.command.type, row.command.payload)
      if (event === null) continue
      if (event.kind === "tree") latest.current.onTree(event.state)
      else if (event.kind === "backup") {
        latest.current.onBackup(event.state, row.receivedAt, String(row.id))
      } else latest.current.onChanges(event.changes, row.receivedAt)
    }
  }, [rows])
}
