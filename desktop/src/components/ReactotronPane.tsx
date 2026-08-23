import { useMemo, useState } from "react"
import { ReactotronFeed, RENDER_WINDOW } from "@/components/ReactotronFeed"
import { ReactotronFilterSheet } from "@/components/ReactotronFilterSheet"
import { ReactotronNotices, ReactotronStatus } from "@/components/ReactotronStatus"
import { ReactotronToolbar } from "@/components/ReactotronToolbar"
import { ReactotronWaiting } from "@/components/ReactotronWaiting"
import { useReactotron } from "@/hooks/useReactotron"
import { asDaemonError, reactotronReverse } from "@/lib/daemon"
import { emptyFilter, filterRows, seenMethods, type TimelineFilter } from "@/lib/reactotron-filter"
import type { Device, ReactotronReverseResponse } from "@/lib/wire"

/**
 * The Reactotron timeline — a live feed of what a React Native app reports.
 *
 * It takes a device rather than requiring one, which is the difference from
 * every other feed here: the relay is a listener on *this* machine and runs
 * with nothing plugged in. A device only matters for the reverse tunnel, and
 * the waiting screen is where that is offered.
 *
 * Mounting subscribes, which is what starts the relay; unmounting stops it.
 */
export function ReactotronPane({ device }: { device: Device | null }) {
  const feed = useReactotron()
  const [filter, setFilter] = useState<TimelineFilter>(emptyFilter)
  const [filtering, setFiltering] = useState(false)
  const [newestFirst, setNewestFirst] = useState(false)
  const [tunnel, setTunnel] = useState<ReactotronReverseResponse | null>(null)
  const [failure, setFailure] = useState<string | null>(null)

  const { timeline } = feed
  const visible = useMemo(() => filterRows(timeline.rows, filter), [timeline.rows, filter])
  const methods = useMemo(
    () => seenMethods(timeline.rows, filter.method),
    [timeline.rows, filter.method],
  )

  const openTunnel = () => {
    if (device === null) return
    setFailure(null)
    reactotronReverse([device.serial], timeline.port).then(setTunnel, (thrown: unknown) => {
      setFailure(asDaemonError(thrown).message)
    })
  }

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
          tunnel={tunnel}
          failure={failure}
          onReverse={openTunnel}
          onRestart={feed.restart}
        />
      </div>
    )
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col bg-bg-root">
      <ReactotronToolbar
        filter={filter}
        onFilter={setFilter}
        visible={visible.length}
        total={timeline.rows.length}
        newestFirst={newestFirst}
        onNewestFirst={setNewestFirst}
        onOpenFilters={() => {
          setFiltering(true)
        }}
        onClear={feed.clear}
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
        onReverse={openTunnel}
      />
      <ReactotronNotices
        error={feed.error?.message ?? null}
        ended={feed.ended}
        failure={failure}
        tunnel={tunnel}
      />
      <ReactotronFeed rows={visible} newestFirst={newestFirst} total={timeline.rows.length} />

      {filtering ? (
        <ReactotronFilterSheet
          filter={filter}
          seenMethods={methods}
          onApply={(applied) => {
            setFilter(applied)
            setFiltering(false)
          }}
          onDismiss={() => {
            setFiltering(false)
          }}
        />
      ) : null}
    </div>
  )
}
