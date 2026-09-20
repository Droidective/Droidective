import { useMemo, useState } from "react"
import {
  ReactotronCommandsPane,
  ReactotronFeed,
  ReactotronReplPane,
  ReactotronFilterSheet,
  ReactotronNotices,
  AppRestartMenu,
  ReactotronStatePane,
  ReactotronStatus,
  ReactotronToolbar,
  ReactotronWaiting,
  RENDER_WINDOW,
  ReverseButton,
  useReactotronCommands,
  useReactotronRepl,
  useReactotronState,
} from "@/components/reactotron"
import { useReactotron } from "@/hooks/useReactotron"
import { useReactotronActions } from "@/hooks/useReactotronActions"
import { emptyFilter, filterRows, seenMethods, type TimelineFilter } from "@/lib/reactotron-filter"
import type { TimelineRow } from "@/lib/reactotron-rows"
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
  const [filter, setFilter] = useState<TimelineFilter>(emptyFilter)
  const [filtering, setFiltering] = useState(false)
  const [newestFirst, setNewestFirst] = useState(false)
  const [view, setView] = useState<ReactotronView>("timeline")

  const { timeline } = feed
  const visible = useMemo(() => filterRows(timeline.rows, filter), [timeline.rows, filter])
  const methods = useMemo(
    () => seenMethods(timeline.rows, filter.method),
    [timeline.rows, filter.method],
  )
  const actions = useReactotronActions({ device, port: timeline.port, visible })
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
        <ReactotronTimelineView
            filter={filter}
            onFilter={setFilter}
            filtering={filtering}
            onFiltering={setFiltering}
            newestFirst={newestFirst}
            onNewestFirst={setNewestFirst}
            feed={feed}
            visible={visible}
            methods={methods}
            actions={actions}
            device={device}
          />
      )}
    </div>
  )
}

/** The timeline half: its toolbar, status, notices, feed and filter sheet. */
function ReactotronTimelineView({
  filter,
  onFilter,
  filtering,
  onFiltering,
  newestFirst,
  onNewestFirst,
  feed,
  visible,
  methods,
  actions,
  device,
}: {
  filter: TimelineFilter
  onFilter: (filter: TimelineFilter) => void
  filtering: boolean
  onFiltering: (filtering: boolean) => void
  newestFirst: boolean
  onNewestFirst: (newestFirst: boolean) => void
  feed: ReturnType<typeof useReactotron>
  visible: TimelineRow[]
  methods: string[]
  actions: ReturnType<typeof useReactotronActions>
  device: Device | null
}) {
  const { timeline } = feed
  return (
    <>
      <ReactotronToolbar
        filter={filter}
        onFilter={onFilter}
        visible={visible.length}
        total={timeline.rows.length}
        newestFirst={newestFirst}
        onNewestFirst={onNewestFirst}
        onOpenFilters={() => {
          onFiltering(true)
        }}
        onClear={feed.clear}
        onExport={actions.exportShown}
        onCopyAll={actions.copyShown}
        trailing={
          <>
            <AppRestartMenu
              serial={device?.serial ?? null}
              subject={{ kind: "client", name: timeline.clients[0]?.name ?? null }}
              onReport={actions.report}
            />
            {/* Beside Restart, as on the Mac. It used to appear only where the
                status bar offers it — while no client is connected — so a
                tunnel that dropped with the client still listed left no way to
                re-open it, which is the one moment you need the button. */}
            <ReverseButton disabled={device === null} onReverse={actions.openTunnel} />
          </>
        }
      />
      <ReactotronStatus
        relay={feed.relay}
        clients={timeline.clients.map((client) => client.name)}
        port={timeline.port}
        rows={timeline.rows.length}
        shown={visible.length}
        rendered={Math.min(visible.length, RENDER_WINDOW)}
        renderWindow={RENDER_WINDOW}
        hasDevice={device !== null}
        onReverse={actions.openTunnel}
      />
      <ReactotronNotices
        error={feed.error?.message ?? null}
        ended={feed.ended}
        failure={actions.failure}
        notice={actions.notice}
        tunnel={actions.tunnel}
      />
      <ReactotronFeed rows={visible} newestFirst={newestFirst} total={timeline.rows.length} />

      {filtering ? (
        <ReactotronFilterSheet
          filter={filter}
          seenMethods={methods}
          onApply={(applied) => {
            onFilter(applied)
            onFiltering(false)
          }}
          onDismiss={() => {
            onFiltering(false)
          }}
        />
      ) : null}
    </>
  )
}

/**
 * The Mac's `viewPicker`, in its order: Timeline, Commands, State, REPL.
 */
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
