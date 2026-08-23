import { cn } from "@/lib/cn"
import { presentation, type BadgeTone, type PrimaryTone, type TimelineRow } from "@/lib/reactotron-rows"
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

/** `HH:mm:ss`, as the Mac's row formats it. */
function clock(at: number): string {
  return new Date(at).toLocaleTimeString("en-GB", { hour12: false })
}

/**
 * One collapsed timeline row: time, badge, an API status when there is one, and
 * the headline.
 *
 * The leading cluster does not shrink, which is what the Mac's `.fixedSize()`
 * buys there — an event type it has no case for is its own name
 * (`SAGA.TASK.COMPLETE`), and a fixed badge column would cut exactly the rows
 * whose badge is the only thing identifying them.
 *
 * Deliberately not clickable yet: expanding a row into its payload is the
 * detail side, and a row that looked interactive without being it would be
 * worse than one that plainly is not.
 */
export function ReactotronRow({ row, hit }: { row: TimelineRow; hit: boolean }) {
  const shown = presentation(row.event)
  return (
    <div
      className={cn(
        "flex items-baseline gap-2 border-b border-border-subtle/50 pr-3",
        hit ? "bg-warn/20" : "",
      )}
    >
      {/* The Mac marks an important event with a bar down the row's edge rather
          than a wash behind it: the relay's disconnect notice sets the flag, and
          that row has to be findable while scrolling past hundreds. */}
      <span className={cn("w-[3px] shrink-0 self-stretch", row.important ? "bg-warn" : "")} />
      <div className="flex shrink-0 items-baseline gap-2 py-1">
        <span className="font-mono text-[11px] text-text-tertiary">{clock(row.receivedAt)}</span>
        <span className={cn("text-[10px] font-bold", BADGE_TONES[shown.badgeTone])}>
          {shown.badge}
        </span>
        {shown.status === undefined ? null : (
          <span
            className={cn("font-mono text-[11px] font-semibold", STATUS_TONES[statusTone(shown.status)])}
            title={
              shown.status === 0 ? "The request failed before a response" : `HTTP ${shown.status}`
            }
          >
            {/* A request that never got a response reports 0 — say so rather
                than showing a status that does not exist. */}
            {shown.status === 0 ? "ERR" : shown.status}
          </span>
        )}
      </div>
      {shown.primary === "" ? null : (
        <span
          className={cn(
            "min-w-0 flex-1 truncate py-1 text-[12px] font-medium",
            PRIMARY_TONES[shown.primaryTone],
          )}
          title={shown.primary}
        >
          {shown.primary}
        </span>
      )}
    </div>
  )
}
