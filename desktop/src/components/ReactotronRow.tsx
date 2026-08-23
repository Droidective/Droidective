import { useState } from "react"
import { ChevronDown, ChevronRight, Copy } from "lucide-react"
import { ReactotronDetail } from "@/components/ReactotronDetail"
import { cn } from "@/lib/cn"
import { copyText } from "@/lib/daemon"
import { copyLine } from "@/lib/reactotron-copy"
import {
  presentation,
  type BadgeTone,
  type PrimaryTone,
  type RowPresentation,
  type TimelineRow,
} from "@/lib/reactotron-rows"
import { statusTone } from "@/lib/reactotron-filter"

/**
 * The one place a tone becomes a colour.
 *
 * The model deals in tones so it can be tested without a renderer; this table
 * is the other half, and it maps one-to-one onto the Mac's `RtPresentation`
 * colours — coral type badges, gold for a name the app chose, the log levels in
 * the theme's own warn and danger.
 */
const BADGE_TONES: Record<BadgeTone, string> = {
  ok: "text-rt-ok",
  type: "text-rt-badge",
  muted: "text-text-tertiary",
  warn: "text-warn",
  error: "text-danger",
}

const PRIMARY_TONES: Record<PrimaryTone, string> = {
  primary: "text-text-primary",
  name: "text-rt-name",
  muted: "text-text-secondary",
}

const STATUS_TONES = {
  ok: "text-rt-ok",
  warn: "text-warn",
  error: "text-danger",
  neutral: "text-rt-number",
}

/**
 * Time, badge and status — the cluster that never shrinks.
 *
 * `.fixedSize()` is what the Mac uses here, and for the same reason: an event
 * type it has no case for *is* its own name (`SAGA.TASK.COMPLETE`), so a fixed
 * badge column would cut exactly the rows whose badge is all that identifies
 * them.
 */
function Lead({
  at,
  shown,
  chevron,
}: {
  at: number
  shown: RowPresentation
  chevron: React.ReactNode
}) {
  return (
    <span className="flex shrink-0 items-baseline gap-2">
      {chevron}
      <span className="font-mono text-[11px] text-text-tertiary">{clock(at)}</span>
      <span className={cn("text-[10px] font-bold", BADGE_TONES[shown.badgeTone])}>{shown.badge}</span>
      {shown.status === undefined ? null : (
        <span
          className={cn("font-mono text-[11px] font-semibold", STATUS_TONES[statusTone(shown.status)])}
          title={shown.status === 0 ? "The request failed before a response" : `HTTP ${shown.status}`}
        >
          {/* A request that never got a response reports 0 — say so rather than
              showing a status that does not exist. */}
          {shown.status === 0 ? "ERR" : shown.status}
        </span>
      )}
    </span>
  )
}

/** `HH:mm:ss`, as the Mac's row formats it. */
function clock(at: number): string {
  return new Date(at).toLocaleTimeString("en-GB", { hour12: false })
}

/**
 * One timeline row: time, badge, an API status when there is one, the headline —
 * and its payload once opened.
 *
 * The whole header is the click target, so nothing has to be aimed at. That
 * costs drag-to-select on the header, which is why copying rides the hover
 * button and the right-click menu, and why the expanded body stays selectable —
 * the same trade the Mac makes, for the same reason.
 */
export function ReactotronRow({
  row,
  onMenu,
}: {
  row: TimelineRow
  /** Right-click, for the copy menu the pane owns. */
  onMenu?: (at: { x: number; y: number }, row: TimelineRow) => void
}) {
  const [expanded, setExpanded] = useState(false)
  const [copied, setCopied] = useState(false)
  const shown = presentation(row.event)
  const Chevron = expanded ? ChevronDown : ChevronRight

  return (
    <div
      className="flex min-w-0 border-b border-border-subtle/50"
      onContextMenu={(event) => {
        if (onMenu === undefined) return
        event.preventDefault()
        onMenu({ x: event.clientX, y: event.clientY }, row)
      }}
    >
      {/* The Mac marks an important event with a bar down the row's edge rather
          than a wash behind it: the relay's disconnect notice sets the flag, and
          that row has to be findable while scrolling past hundreds. */}
      <span className={cn("w-[3px] shrink-0", row.important ? "bg-warn" : "")} />
      <div className="group flex min-w-0 flex-1 flex-col">
        <div className="flex min-w-0 items-baseline gap-2 pr-2">
          <button
            type="button"
            onClick={() => {
              setExpanded(!expanded)
            }}
            aria-expanded={expanded}
            aria-label={expanded ? "Collapse this event" : "Expand this event"}
            className="flex min-w-0 flex-1 items-baseline gap-2 py-1 text-left"
          >
            <Lead at={row.receivedAt} shown={shown} chevron={<Chevron size={11} className="self-center text-text-tertiary" />} />
            {shown.primary === "" ? null : (
              <span
                className={cn("min-w-0 flex-1 truncate text-[12px] font-medium", PRIMARY_TONES[shown.primaryTone])}
                title={shown.primary}
              >
                {shown.primary}
              </span>
            )}
          </button>
          <button
            type="button"
            onClick={() => {
              void copyText(copyLine(row)).then(() => {
                setCopied(true)
                setTimeout(() => {
                  setCopied(false)
                }, 1200)
              })
            }}
            title="Copy this line"
            aria-label="Copy this line"
            className={cn(
              "shrink-0 self-center hover:text-text-primary",
              copied ? "text-accent" : "text-text-tertiary opacity-0 group-hover:opacity-100",
            )}
          >
            <Copy size={11} />
          </button>
        </div>
        {expanded ? (
          <div className="min-w-0 pt-0.5 pr-2 pb-2 pl-[22px]">
            <ReactotronDetail event={row.event} payload={row.command.payload} />
          </div>
        ) : null}
      </div>
    </div>
  )
}
