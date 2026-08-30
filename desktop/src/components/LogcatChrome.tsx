import { Eraser, Pause, Play } from "lucide-react"
import { Banner, Button } from "@/components/Controls"
import { cn } from "@/lib/cn"
import { LOG_CAPACITY, type LogBuffer, type LogRow } from "@/lib/logbuffer"

/**
 * Everything around the feed: the state strip, the notices, and a row.
 *
 * Split out of `LogcatPane` so that file is the feed and its wiring. Nothing
 * here decides anything — the decisions are in `lib/logbuffer.ts` and
 * `lib/logcat-app.ts`, which is where they are tested.
 */

/** How many rows go into the DOM. The buffer holds more; this is what renders. */
export const RENDER_WINDOW = 800

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

/** The Mac app's thin state strip: what the feed is doing, and how much of it. */
export function StatusRow({
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

/** One line of the feed, or the visible marker for a gap the daemon reported. */
export function Row({
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
export function Notices({
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
