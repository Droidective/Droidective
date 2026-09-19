import { useState } from "react"
import { Camera, Eye, ListTree, RotateCcw, Send, Trash2, X } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { JsonTree } from "@/components/JsonTree"
import { StateCard } from "@/components/ReactotronStateCard"
import type { ReactotronStateSession } from "@/hooks/useReactotronState"
import { compactPreview } from "@/lib/json"

/**
 * Reactotron's State screen — the Mac's `statePane`, card for card.
 *
 * Four things, in its order: pull the store, watch paths, dispatch an action,
 * snapshot and restore. All of them work by asking the connected app and
 * reading the answer off the timeline, which is `useReactotronState`'s job;
 * this renders it.
 */
export function ReactotronStatePane({ session }: { session: ReactotronStateSession }) {
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      <div className="flex flex-col gap-3 p-3.5">
        {session.notice === null ? null : <Banner tone="warn">{session.notice}</Banner>}

        <StateTree session={session} />
        <Subscriptions session={session} />
        <Dispatch session={session} />
        <Snapshots session={session} />

        <p className="px-1 text-[11.5px] text-text-tertiary">
          Needs the <code>reactotron-redux</code> or <code>reactotron-mst</code> plugin wired into
          your store.
        </p>
      </div>
    </div>
  )
}

function StateTree({ session }: { session: ReactotronStateSession }) {
  const keys = session.tree !== null && typeof session.tree === "object" && !Array.isArray(session.tree)
    ? Object.keys(session.tree).length
    : null
  return (
    <StateCard
      icon={ListTree}
      title="State tree"
      subtitle="Pull the whole store and drill into any branch."
      chip={keys === null ? null : `${String(keys)} keys`}
      actions={
        <Button onClick={session.loadTree} disabled={session.loadingTree}>
          {session.loadingTree ? "Requesting…" : "Refresh"}
        </Button>
      }
    >
      {session.tree === null ? (
        <Hint
          message={
            session.loadingTree
              ? "Requesting store state…"
              : "Load the current store to browse it as a tree."
          }
        />
      ) : (
        <JsonTree value={session.tree} />
      )}
    </StateCard>
  )
}

function Subscriptions({ session }: { session: ReactotronStateSession }) {
  const [path, setPath] = useState("")
  const add = () => {
    session.addWatch(path)
    setPath("")
  }
  return (
    <StateCard
      icon={Eye}
      title="Subscriptions"
      subtitle="Watch specific paths and see them update live."
      chip={session.watches.length === 0 ? null : `${String(session.watches.length)} watching`}
    >
      <div className="flex items-center gap-2">
        <input
          value={path}
          aria-label="Path to watch"
          placeholder="Path to watch, e.g. user.name"
          onChange={(event) => {
            setPath(event.target.value)
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter") add()
          }}
          className="min-w-0 flex-1 rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1 font-mono text-[12px] text-text-primary outline-none focus:border-accent placeholder:font-sans placeholder:text-text-tertiary"
        />
        <Button onClick={add} disabled={path.trim() === ""}>
          Add
        </Button>
      </div>

      {session.watches.length === 0 ? (
        <Hint message="Add a dot-path above to watch it change in real time." />
      ) : (
        <div className="flex flex-col gap-1.5">
          {session.watches.map((watch) => (
            <div
              key={watch.path}
              className="flex items-start gap-2.5 rounded-md bg-bg-raised px-2.5 py-1.5"
            >
              <div className="min-w-0 flex-1">
                <div className="truncate font-mono text-[12px] font-semibold text-accent">
                  {watch.path}
                </div>
                <div className="truncate font-mono text-[11.5px] text-text-secondary">
                  {watch.value === undefined ? "waiting for a change…" : compactPreview(watch.value, 120)}
                </div>
              </div>
              <button
                type="button"
                title="Stop watching this path"
                aria-label={`Stop watching ${watch.path}`}
                onClick={() => {
                  session.removeWatch(watch.path)
                }}
                className="shrink-0 self-center text-text-tertiary hover:text-text-primary"
              >
                <X size={13} />
              </button>
            </div>
          ))}
        </div>
      )}
    </StateCard>
  )
}

function Dispatch({ session }: { session: ReactotronStateSession }) {
  const [text, setText] = useState("")
  return (
    <StateCard
      icon={Send}
      title="Dispatch action"
      subtitle="Send a Redux action straight to the running app."
    >
      <textarea
        value={text}
        aria-label="Action JSON"
        placeholder={'{ "type": "INCREMENT" }'}
        rows={2}
        onChange={(event) => {
          setText(event.target.value)
        }}
        className="w-full resize-y rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1.5 font-mono text-[12px] text-text-primary outline-none focus:border-accent placeholder:text-text-tertiary"
      />
      <div className="flex justify-end">
        <Button
          tone="primary"
          disabled={text.trim() === ""}
          onClick={() => {
            session.dispatch(text)
          }}
        >
          Dispatch
        </Button>
      </div>
    </StateCard>
  )
}

function Snapshots({ session }: { session: ReactotronStateSession }) {
  return (
    <StateCard
      icon={Camera}
      title="Snapshots"
      subtitle="Freeze the store now, restore it later to reproduce a bug."
      chip={session.snapshots.length === 0 ? null : `${String(session.snapshots.length)} saved`}
      actions={<Button onClick={session.snapshot}>Take Snapshot</Button>}
    >
      {session.snapshots.length === 0 ? (
        <Hint message="Take a snapshot to capture the store as it is right now." />
      ) : (
        <div className="flex flex-col gap-1.5">
          {session.snapshots.map((snapshot) => (
            <div
              key={snapshot.id}
              className="flex items-center gap-2.5 rounded-md bg-bg-raised px-2.5 py-1.5"
            >
              <span className="shrink-0 font-mono text-[11.5px] tabular-nums text-text-tertiary">
                {new Date(snapshot.takenAt).toLocaleTimeString([], { hour12: false })}
              </span>
              <span className="min-w-0 flex-1 truncate font-mono text-[11.5px] text-text-secondary">
                {compactPreview(snapshot.state, 120)}
              </span>
              <button
                type="button"
                title="Restore this snapshot"
                aria-label="Restore this snapshot"
                onClick={() => {
                  session.restore(snapshot)
                }}
                className="shrink-0 text-text-tertiary hover:text-text-primary"
              >
                <RotateCcw size={13} />
              </button>
              <button
                type="button"
                title="Delete this snapshot"
                aria-label="Delete this snapshot"
                onClick={() => {
                  session.deleteSnapshot(snapshot.id)
                }}
                className="shrink-0 text-text-tertiary hover:text-danger"
              >
                <Trash2 size={13} />
              </button>
            </div>
          ))}
        </div>
      )}
    </StateCard>
  )
}

function Hint({ message }: { message: string }) {
  return <p className="px-1 py-2 text-[12px] text-text-tertiary">{message}</p>
}
