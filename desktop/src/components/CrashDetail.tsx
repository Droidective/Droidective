import { KindChip } from "@/components/CrashList"
import { Switch } from "@/components/Controls"
import type { CrashReport } from "@/lib/wire"

/**
 * One crash's trace.
 *
 * Raw log switches between the two renderings the daemon already sent — the
 * original threadtime lines, or just the messages. Both travel because
 * deriving one from the other means reimplementing logcat's prefix strip.
 */
export function CrashDetail({
  crash,
  showRaw,
  onShowRaw,
}: {
  crash: CrashReport
  showRaw: boolean
  onShowRaw: (on: boolean) => void
}) {
  return (
    <div className="flex min-w-0 flex-1 flex-col">
      <header className="flex shrink-0 flex-wrap items-center gap-2.5 border-b border-border-subtle px-3 py-2">
        <KindChip crash={crash} />
        {crash.process === null ? null : (
          <span className="font-mono text-[12px] text-text-primary">{crash.process}</span>
        )}
        {crash.pid === null ? null : (
          <span className="text-[12px] text-text-secondary">PID {crash.pid}</span>
        )}
        {crash.timestamp === null ? null : (
          <span className="font-mono text-[11.5px] text-text-tertiary">{crash.timestamp}</span>
        )}
        <span className="ml-auto">
          <Switch
            checked={showRaw}
            onChange={onShowRaw}
            label="Raw log"
            ariaLabel="Show the original logcat lines instead of just the messages"
          />
        </span>
      </header>

      <div className="min-h-0 flex-1 overflow-auto p-3" data-selectable>
        <pre className="whitespace-pre-wrap break-all font-mono text-[11.5px] leading-[1.5] text-text-primary">
          {showRaw ? crash.raw : crash.body}
        </pre>
      </div>
    </div>
  )
}
