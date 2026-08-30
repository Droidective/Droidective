import { useMemo, useRef, useState } from "react"
import { NoDevice } from "@/components/NoDevice"
import { Notices, RENDER_WINDOW, Row, StatusRow } from "@/components/LogcatChrome"
import { LogcatToolbar } from "@/components/LogcatToolbar"
import { useLogcatAppFilter, type LogcatAppFilter } from "@/hooks/useLogcatAppFilter"
import { useLogcatStream, type LogcatStream } from "@/hooks/useLogcatStream"
import { asDaemonError, exportText } from "@/lib/daemon"
import {
  emptyFilter,
  logText,
  matchesFind,
  matchesLogFilter,
  tagsByFrequency,
  type LogBuffer,
  type LogFilter,
  type LogRow,
} from "@/lib/logbuffer"
import type { Device } from "@/lib/wire"

export function LogcatPane({
  device,
  packageId,
  onSelectPackage,
}: {
  device: Device | null
  /** The app chosen in Apps — what the log narrows to when the filter is on. */
  packageId: string | null
  onSelectPackage: (packageId: string | null) => void
}) {
  const serial = device?.serial ?? null
  const [failure, setFailure] = useState<string | null>(null)
  const app = useLogcatAppFilter({ serial, packageId, onSelectPackage, onError: setFailure })
  const stream = useLogcatStream(serial, app.pid)
  const [filter, setFilter] = useState<LogFilter>(emptyFilter)
  const [find, setFind] = useState("")
  const [following, setFollowing] = useState(true)
  const [saved, setSaved] = useState<string | null>(null)
  const scroller = useRef<HTMLDivElement | null>(null)

  const { buffer } = stream
  const visible = useMemo(
    () => buffer.rows.filter((row) => matchesLogFilter(row, filter)),
    [buffer.rows, filter],
  )
  const rendered = visible.slice(Math.max(0, visible.length - RENDER_WINDOW))
  const tags = useMemo(() => tagsByFrequency(buffer.rows).slice(0, 40), [buffer.rows])
  const hits = useMemo(
    () => (find.trim() === "" ? 0 : visible.filter((row) => matchesFind(row, find)).length),
    [visible, find],
  )

  // Pinning to the bottom is a layout effect in spirit, but it only has to
  // happen after the rows are in the DOM, which this is.
  const pin = (element: HTMLDivElement | null) => {
    scroller.current = element
    if (element && following) element.scrollTop = element.scrollHeight
  }

  const jumpToNewest = () => {
    setFollowing(true)
    if (scroller.current) scroller.current.scrollTop = scroller.current.scrollHeight
  }

  if (!device) {
    return <NoDevice feature="logcat" title="Logcat" />
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col bg-bg-root">
      <Header
        filter={filter}
        onFilter={setFilter}
        find={find}
        onFind={setFind}
        hits={hits}
        tags={tags}
        app={app}
        packageId={packageId}
        stream={stream}
        buffer={buffer}
        shown={visible.length}
        rendered={rendered.length}
        following={following}
        onFollow={jumpToNewest}
        saved={saved}
        failure={failure}
        onExport={() => {
          void saveLog(visible).then(setSaved, (thrown: unknown) => {
            setFailure(asDaemonError(thrown).message)
          })
        }}
      />

      <Feed
        rows={rendered}
        find={find}
        pin={pin}
        onFollowing={setFollowing}
        onTag={(tag) => {
          setFilter((current) =>
            current.tags.includes(tag) ? current : { ...current, tags: [...current.tags, tag] },
          )
        }}
      />
    </div>
  )
}

/**
 * The rows, and the one piece of state the pane cannot read from anywhere else:
 * whether the reader has scrolled away from the newest line.
 *
 * Following is decided from a real scroll position rather than inferred from
 * the programmatic pin — the Mac learned that the read-back cannot drive a
 * follow decision under streaming load, and the same is true of a DOM that is
 * being appended to several times a second.
 */
function Feed({
  rows,
  find,
  pin,
  onFollowing,
  onTag,
}: {
  rows: readonly LogRow[]
  find: string
  pin: (element: HTMLDivElement | null) => void
  onFollowing: (following: boolean) => void
  onTag: (tag: string) => void
}) {
  return (
    <div
      ref={pin}
      onScroll={(event) => {
        const element = event.currentTarget
        onFollowing(element.scrollHeight - element.scrollTop - element.clientHeight < 24)
      }}
      className="min-h-0 flex-1 overflow-y-auto px-3 py-1.5 font-mono text-[11.5px] leading-[1.5]"
      data-selectable
    >
      {rows.map((row) => (
        <Row key={row.key} row={row} hit={matchesFind(row, find)} onTag={onTag} />
      ))}
    </div>
  )
}

/**
 * Everything above the rows, in one place.
 *
 * A component rather than three siblings inside the pane: the toolbar, the
 * state strip and the notices are one band of chrome, and threading their
 * seventeen props through the pane's own body is what pushed it past being
 * readable.
 */
function Header({
  filter,
  onFilter,
  find,
  onFind,
  hits,
  tags,
  app,
  packageId,
  stream,
  buffer,
  shown,
  rendered,
  following,
  onFollow,
  saved,
  failure,
  onExport,
}: {
  filter: LogFilter
  onFilter: (filter: LogFilter) => void
  find: string
  onFind: (find: string) => void
  hits: number
  tags: string[]
  app: LogcatAppFilter
  packageId: string | null
  stream: LogcatStream
  buffer: LogBuffer
  shown: number
  rendered: number
  following: boolean
  onFollow: () => void
  saved: string | null
  failure: string | null
  onExport: () => void
}) {
  return (
    <>
      <LogcatToolbar
        filter={filter}
        onFilter={onFilter}
        find={find}
        onFind={onFind}
        hits={hits}
        tags={tags}
        appFilter={app.filter}
        packageId={packageId}
        canNarrow={packageId !== null}
        narrowed={app.narrowed}
        onNarrow={app.setNarrowed}
        onUseForegroundApp={app.useForegroundApp}
        onExport={onExport}
      />

      <StatusRow
        streaming={stream.streaming}
        buffer={buffer}
        shown={shown}
        rendered={rendered}
        following={following}
        onFollow={onFollow}
        onClear={stream.clear}
        onStop={() => void stream.stop()}
        onRestart={stream.restart}
      />

      <Notices
        error={stream.error?.message ?? null}
        ended={stream.ended}
        failure={failure}
        saved={saved}
      />

    </>
  )
}

/** Writes what is on screen, named for when it was taken. */
function saveLog(rows: readonly LogRow[]): Promise<string> {
  const stamp = new Date().toISOString().replaceAll(/[:.]/gu, "-").slice(0, 19)
  return exportText(`logcat_${stamp}.txt`, logText(rows))
}
