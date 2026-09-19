import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from "react"
import { asDaemonError, watchPull } from "@/lib/daemon"
import { apply, dismissDelay, started, type PullState } from "@/lib/pull-progress"

/**
 * The pulls in flight, and the strip that shows them.
 *
 * App-wide rather than per-screen, because the Mac's strip is: it lives in the
 * window's safe-area inset, and a pull started from the File Explorer keeps
 * reporting while somebody switches to another tab. A hook owned by the screen
 * would lose the transfer the moment the pane changed.
 */
export interface Pulls {
  active: PullState[]
  /** Starts a pull, reporting into the strip. Resolves where it landed. */
  start: (args: { serial: string; path: string; asRoot: boolean }) => Promise<string | null>
  /** Stops a pull. The daemon's task is cancelled, which kills the adb child. */
  cancel: (path: string) => void
  dismiss: (path: string) => void
}

const PullsContext = createContext<Pulls | null>(null)

export function PullsProvider({ children }: { children: ReactNode }) {
  const [active, setActive] = useState<PullState[]>([])
  /** The live subscriptions, keyed by device path — what Cancel stops. */
  const running = useRef(new Map<string, { stop: () => Promise<void> }>())

  const remove = useCallback((path: string) => {
    setActive((current) => current.filter((pull) => pull.path !== path))
    running.current.delete(path)
  }, [])

  const start = useCallback(
    (args: { serial: string; path: string; asRoot: boolean }) => {
      setActive((current) => [
        ...current.filter((pull) => pull.path !== args.path),
        started(args.path),
      ])
      return new Promise<string | null>((resolve) => {
        void watchPull(args, (update) => {
          if (update.event === "batch") {
            for (const item of update.items) {
              setActive((current) =>
                current.map((pull) => (pull.path === args.path ? apply(pull, item) : pull)),
              )
              if (!item.done) continue
              resolve(item.path)
              // A finished pull clears itself; a failed one stays until it is
              // dismissed, because an error that vanishes is one nobody read.
              const delay = dismissDelay(apply(started(args.path), item))
              if (delay !== null) globalThis.setTimeout(() => {
                remove(args.path)
              }, delay)
            }
            return
          }
          if (update.event === "failed") {
            setActive((current) =>
              current.map((pull) =>
                pull.path === args.path
                  ? { ...pull, done: true, failure: update.message }
                  : pull,
              ),
            )
            resolve(null)
          }
        })
          .then((subscription) => {
            running.current.set(args.path, subscription)
          })
          .catch((thrown: unknown) => {
            setActive((current) =>
              current.map((pull) =>
                pull.path === args.path
                  ? { ...pull, done: true, failure: asDaemonError(thrown).message }
                  : pull,
              ),
            )
            resolve(null)
          })
      })
    },
    [remove],
  )

  const value = useMemo<Pulls>(
    () => ({
      active,
      start,
      cancel: (path: string) => {
        void running.current.get(path)?.stop()
        remove(path)
      },
      dismiss: remove,
    }),
    [active, remove, start],
  )

  return <PullsContext value={value}>{children}</PullsContext>
}

export function usePulls(): Pulls {
  const value = useContext(PullsContext)
  if (value === null) throw new Error("usePulls used outside PullsProvider")
  return value
}
