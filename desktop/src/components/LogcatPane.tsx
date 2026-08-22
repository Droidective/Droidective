import { useMemo, useRef, useState } from "react"
import { Eraser, Pause, Play } from "lucide-react"
import { NoDevice } from "@/components/NoDevice"
import { Banner, Button } from "@/components/Controls"
import { LogcatToolbar } from "@/components/LogcatToolbar"
import { useLogcatStream } from "@/hooks/useLogcatStream"
import { cn } from "@/lib/cn"
import { asDaemonError, exportText } from "@/lib/daemon"
import {
  emptyFilter,
  LOG_CAPACITY,
  logText,
  matchesFind,
  matchesLogFilter,
  tagsByFrequency,
  type LogBuffer,
  type LogFilter,
  type LogRow,
} from "@/lib/logbuffer"
import type { Device } from "@/lib/wire"

/** How many rows go into the DOM. The buffer holds more; this is what renders. */
const RENDER_WINDOW = 800

/**
 * Level colouring, following the Mac app's log view: the noise (verbose and
 * debug) recedes, info reads as normal weight text, and anything worse is
 * coloured. Guessing at a line's importance is the whole job of a log view.
 */
const LEVEL_STYLES: Record<string, string> = {
  V: "text-text-tertiary",
  D: "text-text-secondary",
  I: "text-text-primary",
  W: "text-warn",
  E: "text-danger",
  F: "text-danger",
}

export function LogcatPane({ device }: { device: Device | null }) {
  const stream = useLogcatStream(device?.serial ?? null)
  const [filter, setFilter] = useState<LogFilter>(emptyFilter)
  const [find, setFind] = useState("")
  const [following, setFollowing] = useState(true)
  const [saved, setSaved] = useState<string | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
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

  if (!device) {
    return <NoDevice feature="logcat" title="Logcat" />
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col bg-bg-root">
      <LogcatToolbar
        filter={filter}
        onFilter={setFilter}
        find={find}
        onFind={setFind}
        hits={hits}
        tags={tags}
        onExport={() => {
          void saveLog(visible).then(setSaved, (thrown: unknown) => {
            setFailure(asDaemonError(thrown).message)
          })
        }}
      />

      <StatusRow
        streaming={stream.streaming}
        buffer={buffer}
        shown={visible.length}
        rendered={rendered.length}
        following={following}
        onFollow={() => {
          setFollowing(true)
          if (scroller.current) scroller.current.scrollTop = scroller.current.scrollHeight
        }}
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

      <div
        ref={pin}
        onScroll={(event) => {
          // Following is a decision about intent, so it is read from a real
          // scroll position rather than inferred from a programmatic pin.
          const element = event.currentTarget
          setFollowing(element.scrollHeight - element.scrollTop - element.clientHeight < 24)
        }}
        className="min-h-0 flex-1 overflow-y-auto px-3 py-1.5 font-mono text-[11.5px] leading-[1.5]"
        data-selectable
      >
        {rendered.map((row) => (
          <Row
            key={row.key}
            row={row}
            hit={matchesFind(row, find)}
            onTag={(tag) => {
              setFilter((current) =>
                current.tags.includes(tag)
                  ? current
                  : { ...current, tags: [...current.tags, tag] },
              )
            }}
          />
        ))}
      </div>
    </div>
  )
}

/** Writes what is on screen, named for when it was taken. */
function saveLog(rows: readonly LogRow[]): Promise<string> {
  const stamp = new Date().toISOString().replaceAll(/[:.]/gu, "-").slice(0, 19)
  return exportText(`logcat_${stamp}.txt`, logText(rows))
}

/** The Mac app's thin state strip: what the feed is doing, and how much of it. */
function StatusRow({
  streaming,
  buffer,
  shown,
  rendered,
  following,
  onFollow,
  onClear,
  onStop,
  onRestart,
}: {
  streaming: boolean
  buffer: LogBuffer
  shown: number
  rendered: number
  following: boolean
  onFollow: () => void
  onClear: () => void
  onStop: () => void
  onRestart: () => void
}) {
  // Every cap says so out loud. A feed that quietly shows a subset is a feed
  // that lies about being complete.
  const notes: string[] = []
  if (shown > rendered) notes.push(`rendering the last ${RENDER_WINDOW.toLocaleString()}`)
  if (buffer.rows.length >= LOG_CAPACITY) {
    notes.push(`buffering the last ${LOG_CAPACITY.toLocaleString()}`)
  }
  if (buffer.dropped > 0) notes.push(`${buffer.dropped.toLocaleString()} dropped`)

  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle bg-bg-surface px-3 py-1">
      <span
        className={cn("h-1.5 w-1.5 rounded-full", streaming ? "bg-accent" : "bg-text-tertiary")}
      />
      <span className="text-[11.5px] text-text-secondary">
        {streaming ? "Streaming" : "Stopped"}
      </span>
      <span className="flex-1" />
      <span className="text-[11.5px] text-text-tertiary">
        {[`${shown.toLocaleString()} lines`, ...notes].join(" · ")}
      </span>
      {following ? null : (
        <Button onClick={onFollow} title="Scroll back to the newest line">
          Jump to newest
        </Button>
      )}
      <Button onClick={onClear} title="Clear what is on screen">
        <span className="flex items-center gap-1.5">
          <Eraser size={13} />
          Clear
        </span>
      </Button>
      {/* Stop used to be a one-way door: the only way back was a tab switch. */}
      {streaming ? (
        <Button onClick={onStop} title="Stop streaming">
          <span className="flex items-center gap-1.5">
            <Pause size={13} />
            Stop
          </span>
        </Button>
      ) : (
        <Button onClick={onRestart} tone="primary" title="Start streaming again">
          <span className="flex items-center gap-1.5">
            <Play size={13} />
            Start
          </span>
        </Button>
      )}
    </div>
  )
}

function Row({
  row,
  hit,
  onTag,
}: {
  row: LogRow
  hit: boolean
  onTag: (tag: string) => void
}) {
  if (row.kind === "gap") {
    return (
      <div className="my-1 flex items-center gap-2 text-warn">
        <span className="h-px flex-1 bg-warn/40" />
        <span className="text-[11px]">{row.count.toLocaleString()} lines dropped</span>
        <span className="h-px flex-1 bg-warn/40" />
      </div>
    )
  }
  const { line } = row
  // `time  pid  L/Tag: message`, the shape adb prints and the Mac app keeps.
  return (
    <div
      className={cn(
        "whitespace-pre-wrap break-words",
        LEVEL_STYLES[line.level] ?? "text-text-secondary",
        // Find highlights rather than hides — that is the point of the split.
        hit ? "rounded-sm bg-warn/20" : "",
      )}
    >
      <span className="text-text-tertiary">{line.time} </span>
      <span className="text-text-tertiary">{line.pid.padStart(5, " ")} </span>
      <span>{line.level}/</span>
      <button
        type="button"
        onClick={() => {
          onTag(line.tag)
        }}
        title={`Show only ${line.tag}`}
        className="underline decoration-dotted underline-offset-2 hover:text-accent"
      >
        {line.tag}
      </button>
      <span>: </span>
      {line.message}
    </div>
  )
}

/** Whatever the feed has to say for itself, above the rows. */
function Notices({
  error,
  ended,
  failure,
  saved,
}: {
  error: string | null
  ended: string | null
  failure: string | null
  saved: string | null
}) {
  const notices: { tone: "error" | "warn" | "ok"; text: string }[] = []
  if (error !== null) notices.push({ tone: "error", text: error })
  else if (ended !== null) notices.push({ tone: "warn", text: `The log stream ended (${ended}).` })
  if (failure !== null) notices.push({ tone: "error", text: failure })
  if (saved !== null) notices.push({ tone: "ok", text: `Saved to ${saved}` })
  if (notices.length === 0) return null
  return (
    <div className="flex shrink-0 flex-col gap-2 px-3 pt-3">
      {notices.map((notice) => (
        <Banner key={notice.text} tone={notice.tone}>
          {notice.text}
        </Banner>
      ))}
    </div>
  )
}
