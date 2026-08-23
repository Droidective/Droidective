import { Banner } from "@/components/Controls"
import type { RelayState } from "@/hooks/useReactotron"
import { cn } from "@/lib/cn"
import { MAX_ROWS } from "@/lib/reactotron-buffer"
import type { ReactotronReverseResponse } from "@/lib/wire"

/**
 * The thin state strip under the toolbar: who is connected, how much is shown,
 * and every cap that is in force.
 *
 * Naming the caps is the point. A feed that quietly renders a subset is a feed
 * that lies about being complete, and the moment someone doubts it they stop
 * trusting the whole screen.
 */
export function ReactotronStatus({
  relay,
  clients,
  port,
  rows,
  shown,
  rendered,
  renderWindow,
  hasDevice,
  onReverse,
}: {
  relay: RelayState
  clients: string[]
  port: number | null
  rows: number
  shown: number
  rendered: number
  renderWindow: number
  hasDevice: boolean
  onReverse: () => void
}) {
  const notes: string[] = []
  if (shown > rendered) notes.push(`rendering the last ${renderWindow.toLocaleString()}`)
  if (rows >= MAX_ROWS) notes.push(`buffering the last ${MAX_ROWS.toLocaleString()}`)

  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle bg-bg-surface px-3 py-1">
      <span
        className={cn(
          "size-1.5 shrink-0 rounded-full",
          relay === "connected" ? "bg-rt-ok" : relay === "failed" ? "bg-danger" : "bg-warn",
        )}
      />
      <span className="min-w-0 truncate text-[11.5px] text-text-secondary">
        {clients.length === 0
          ? `Listening on :${port ?? 9090} — no app connected`
          : clients.join(" · ")}
      </span>
      <span className="flex-1" />
      <span className="shrink-0 text-[11.5px] text-text-tertiary tabular-nums">
        {[`${rows.toLocaleString()} events`, ...notes].join(" · ")}
      </span>
      {/* Offered here as well as on the waiting screen, because this is where
          someone ends up when an app connected once and then stopped. */}
      {clients.length === 0 && hasDevice ? (
        <button
          type="button"
          onClick={onReverse}
          title="adb reverse tcp:9090 tcp:9090 — lets the device reach the relay"
          className="shrink-0 rounded-md bg-bg-raised px-2 py-0.5 text-[11.5px] text-text-secondary hover:text-text-primary"
        >
          Open tunnel
        </button>
      ) : null}
    </div>
  )
}

/** Whatever the feed has to say for itself, above the rows. */
export function ReactotronNotices({
  error,
  ended,
  failure,
  notice,
  tunnel,
}: {
  error: string | null
  ended: string | null
  failure: string | null
  /** Something that went right and is worth saying — an export, a restart. */
  notice?: string | null
  tunnel: ReactotronReverseResponse | null
}) {
  const notices: { tone: "error" | "warn" | "ok"; text: string }[] = []
  if (error !== null) notices.push({ tone: "error", text: error })
  else if (ended !== null) notices.push({ tone: "warn", text: `The relay stopped (${ended}).` })
  if (failure !== null) notices.push({ tone: "error", text: failure })
  if (notice !== null && notice !== undefined) notices.push({ tone: "ok", text: notice })
  for (const result of tunnel?.results ?? []) {
    // adb's own words, because "device offline" and "more than one device" want
    // different things done about them.
    if (result.ok) continue
    notices.push({
      tone: "error",
      text: `${result.serial}: ${result.detail === "" ? "adb refused the tunnel" : result.detail}`,
    })
  }
  if (notices.length === 0) return null
  return (
    <div className="flex shrink-0 flex-col gap-2 px-3 pt-3">
      {notices.map((entry) => (
        <Banner key={entry.text} tone={entry.tone}>
          {entry.text}
        </Banner>
      ))}
    </div>
  )
}
