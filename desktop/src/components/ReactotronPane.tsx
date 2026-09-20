import { useState } from "react"
import {
  ReactotronCommandsPane,
  ReactotronReplPane,
  ReactotronStatePane,
  ReactotronTimeline,
  ReactotronWaiting,
  useReactotronCommands,
  useReactotronRepl,
  useReactotronState,
} from "@/components/reactotron"
import { useReactotron } from "@/hooks/useReactotron"
import { useReactotronActions } from "@/hooks/useReactotronActions"
import type { Device } from "@/lib/wire"

/**
 * The Reactotron timeline — a live feed of what a React Native app reports.
 *
 * It takes a device rather than requiring one, which is the difference from
 * every other feed here: the relay is a listener on *this* machine and runs
 * with nothing plugged in. A device only matters for the reverse tunnel and the
 * restart, and the waiting screen is where the tunnel is offered.
 *
 * Mounting subscribes, which is what starts the relay; unmounting stops it.
 */
export function ReactotronPane({ device }: { device: Device | null }) {
  const feed = useReactotron()
  const [view, setView] = useState<ReactotronView>("timeline")

  const { timeline } = feed
  // The export and the copy-all act on the whole timeline rather than one
  // pane's view of it: with the split open there are two views, and picking
  // one of them would make what the button writes depend on which pane you
  // last touched.
  const actions = useReactotronActions({ device, port: timeline.port, visible: timeline.rows })
  // Fed the raw rows, not the filtered ones: a `state.values.response` the user
  // has filtered out of view is still the answer this screen asked for.
  const state = useReactotronState(timeline.rows)
  const repl = useReactotronRepl(timeline.rows)
  const custom = useReactotronCommands(timeline.rows)

  // The waiting screen gives way only once there is something to read. A relay
  // whose app has since disconnected still has rows, and those last events are
  // usually exactly what someone came for.
  if (feed.relay !== "connected" && timeline.rows.length === 0) {
    return (
      <div className="flex min-h-0 flex-1 flex-col bg-bg-root">
        <ReactotronWaiting
          relay={feed.relay}
          port={timeline.port}
          error={feed.error?.message ?? feed.ended}
          hasDevice={device !== null}
          tunnel={actions.tunnel}
          failure={actions.failure}
          onReverse={actions.openTunnel}
          onRestart={feed.restart}
        />
      </div>
    )
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col bg-bg-root">
      <ReactotronViewPicker view={view} onView={setView} />
      {view === "state" ? (
        <ReactotronStatePane session={state} />
      ) : view === "repl" ? (
        <ReactotronReplPane session={repl} />
      ) : view === "commands" ? (
        <ReactotronCommandsPane session={custom} />
      ) : (
<ReactotronTimeline feed={feed} actions={actions} device={device} />
      )}
    </div>
  )
}

type ReactotronView = "timeline" | "commands" | "state" | "repl"

function ReactotronViewPicker({
  view,
  onView,
}: {
  view: ReactotronView
  onView: (view: ReactotronView) => void
}) {
  return (
    <div className="flex shrink-0 items-center gap-1 border-b border-border-subtle bg-bg-chrome px-3 py-1.5">
      {(["timeline", "commands", "state", "repl"] as const).map((option) => (
        <button
          key={option}
          type="button"
          aria-pressed={view === option}
          onClick={() => {
            onView(option)
          }}
          className={
            view === option
              ? "rounded-md bg-accent/20 px-2.5 py-0.5 text-[11.5px] capitalize text-accent"
              : "rounded-md px-2.5 py-0.5 text-[11.5px] capitalize text-text-secondary hover:text-text-primary"
          }
        >
          {option}
        </button>
      ))}
    </div>
  )
}
