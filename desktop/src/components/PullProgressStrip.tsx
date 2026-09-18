import { FolderOpen, X } from "lucide-react"
import { IconButton } from "@/components/Hub"
import { usePulls } from "@/hooks/usePulls"
import { revealPath } from "@/lib/daemon"
import { caption, fraction, leafName, type PullState } from "@/lib/pull-progress"

/**
 * The pull progress strip — the Mac's, in the window's safe-area inset.
 *
 * Above the content rather than inside any pane, for the Mac's reason: a pull
 * started from the File Explorer keeps running while somebody switches tabs,
 * and a strip that belonged to a screen would vanish with it. The Mac puts it
 * in `RootView`'s safe-area inset rather than inside `DeviceBarView` for the
 * same reason.
 */
export function PullProgressStrip() {
  const pulls = usePulls()
  if (pulls.active.length === 0) return null

  return (
    <div className="flex flex-col border-b border-border-subtle bg-bg-chrome">
      {pulls.active.map((pull) => (
        <Row
          key={pull.path}
          pull={pull}
          onCancel={() => {
            pulls.cancel(pull.path)
          }}
          onDismiss={() => {
            pulls.dismiss(pull.path)
          }}
        />
      ))}
    </div>
  )
}

function Row({
  pull,
  onCancel,
  onDismiss,
}: {
  pull: PullState
  onCancel: () => void
  onDismiss: () => void
}) {
  const ratio = fraction(pull)
  return (
    <div className="flex items-center gap-3 px-3 py-1.5">
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <div className="flex items-baseline gap-2">
          <span className="min-w-0 truncate text-[12px] text-text-primary" title={pull.path}>
            {leafName(pull.path)}
          </span>
          <span
            className={
              pull.failure === null
                ? "min-w-0 flex-1 truncate text-[11.5px] text-text-tertiary"
                : "min-w-0 flex-1 truncate text-[11.5px] text-danger"
            }
          >
            {caption(pull)}
          </span>
        </div>
        <div className="h-1 overflow-hidden rounded-full bg-border-subtle">
          {ratio === null ? (
            // Indeterminate: no total to divide by, so the bar paces rather
            // than claiming a percentage it does not have.
            <div
              className={
                pull.done
                  ? "h-full w-full bg-accent"
                  : "h-full w-1/3 animate-pulse rounded-full bg-accent"
              }
            />
          ) : (
            <div
              className="h-full rounded-full bg-accent transition-[width] duration-200"
              style={{ width: `${ratio * 100}%` }}
            />
          )}
        </div>
      </div>

      {pull.done && pull.landedAt !== null ? (
        <IconButton
          icon={<FolderOpen size={14} />}
          label="Show in folder"
          onClick={() => {
            if (pull.landedAt !== null) void revealPath(pull.landedAt)
          }}
        />
      ) : null}
      <IconButton
        icon={<X size={14} />}
        label={pull.done ? "Dismiss" : "Cancel pull"}
        onClick={pull.done ? onDismiss : onCancel}
      />
    </div>
  )
}
