import { useEffect, useRef, useState } from "react"
import { Pause, Search } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { useLogcatStream } from "@/hooks/useLogcatStream"
import { cn } from "@/lib/cn"
import { LOG_CAPACITY, matchesFilter, type LogBuffer, type LogRow } from "@/lib/logbuffer"
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
  const { buffer, streaming, error, ended, stop } = useLogcatStream(device?.serial ?? null)
  const [filter, setFilter] = useState("")
  const [following, setFollowing] = useState(true)
  const scroller = useRef<HTMLDivElement | null>(null)

  const visible = buffer.rows.filter((row) => matchesFilter(row, filter))
  const rendered = visible.slice(Math.max(0, visible.length - RENDER_WINDOW))

  useEffect(() => {
    if (!following) return
    const element = scroller.current
    if (element) element.scrollTop = element.scrollHeight
  }, [rendered.length, following])

  if (!device) {
    return <p className="p-6 text-text-tertiary">Connect a device to read its log.</p>
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col bg-bg-root">
      <div className="flex shrink-0 items-center gap-3 border-b border-border-subtle bg-bg-chrome px-3 py-2">
        <div className="flex w-72 items-center gap-2 rounded-md border border-border-subtle bg-bg-raised px-2.5 py-1 focus-within:border-accent">
          <Search size={13} className="shrink-0 text-text-tertiary" />
          <input
            value={filter}
            aria-label="Filter lines"
            placeholder="Search lines…"
            onChange={(event) => {
              setFilter(event.target.value)
            }}
            className="min-w-0 flex-1 bg-transparent text-[13px] text-text-primary outline-none placeholder:text-text-tertiary"
          />
        </div>
        <div className="flex-1" />
        {following ? null : (
          <Button
            onClick={() => {
              setFollowing(true)
            }}
          >
            Jump to newest
          </Button>
        )}
        <Button onClick={() => void stop()} disabled={!streaming} title="Stop streaming">
          <span className="flex items-center gap-1.5">
            <Pause size={13} />
            Stop
          </span>
        </Button>
      </div>

      <StatusRow
        streaming={streaming}
        buffer={buffer}
        shown={visible.length}
        rendered={rendered.length}
      />

      {error ? (
        <div className="px-3 pt-3">
          <Banner tone="error">{error.message}</Banner>
        </div>
      ) : null}
      {ended !== null && !error ? (
        <div className="px-3 pt-3">
          <Banner tone="warn">The log stream ended ({ended}).</Banner>
        </div>
      ) : null}

      <div
        ref={scroller}
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
          <Row key={row.key} row={row} />
        ))}
      </div>
    </div>
  )
}

/** The Mac app's thin state strip: what the feed is doing, and how much of it. */
function StatusRow({
  streaming,
  buffer,
  shown,
  rendered,
}: {
  streaming: boolean
  buffer: LogBuffer
  shown: number
  rendered: number
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
    </div>
  )
}

function Row({ row }: { row: LogRow }) {
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
      )}
    >
      <span className="text-text-tertiary">{line.time} </span>
      <span className="text-text-tertiary">{line.pid.padStart(5, " ")} </span>
      <span>
        {line.level}/{line.tag}:{" "}
      </span>
      {line.message}
    </div>
  )
}
