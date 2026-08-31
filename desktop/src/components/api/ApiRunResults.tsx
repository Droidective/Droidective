import { CircleCheck, CirclePlay, CircleX } from "lucide-react"

import { EmptyNote } from "@/components/api/ApiKit"
import { TextInput } from "@/components/Controls"
import { methodColor, statusColor } from "@/lib/api/labels"
import { rowPassed, type RunRow } from "@/lib/api/runner"
import { cn } from "@/lib/cn"

/**
 * The runner's rows, and the two number boxes above them.
 *
 * Split from `ApiRunnerSheet` for its line budget; the Mac keeps them in the
 * same sheet.
 */

export function ApiRunResults({ rows, running }: { rows: RunRow[]; running: boolean }) {
  if (rows.length === 0) {
    return running ? (
      <EmptyNote title="Running…" />
    ) : (
      <div className="flex min-h-[180px] flex-col items-center justify-center gap-2">
        <CirclePlay size={24} className="text-text-tertiary" />
        <p className="text-[12px] text-text-secondary">
          Run to see each request&apos;s result and its tests.
        </p>
      </div>
    )
  }

  return (
    <div className="max-h-[280px] min-h-[180px] overflow-auto">
      {rows.map((row) => (
        <div key={row.id} className="flex items-start gap-2 py-1">
          {rowPassed(row) ? (
            <CircleCheck size={13} className="mt-0.5 shrink-0 text-accent" />
          ) : (
            <CircleX size={13} className="mt-0.5 shrink-0 text-danger" />
          )}
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className={cn("font-mono text-[10px]", methodColor(row.method))}>
                {row.method}
              </span>
              <span className="text-[12px] text-text-primary">{row.name}</span>
              {row.path.length === 0 ? null : (
                <span className="text-[10px] text-text-tertiary">{row.path.join(" / ")}</span>
              )}
            </div>
            {row.errorText === null ? (
              <FailedAssertion row={row} />
            ) : (
              <p className="text-[11px] text-danger">{row.errorText}</p>
            )}
          </div>
          {row.statusCode === null ? null : (
            <span className={cn("font-mono text-[12px]", statusColor(row.statusCode))}>
              {row.statusCode}
            </span>
          )}
          {row.elapsedMs === null ? null : (
            <span className="font-mono text-[11px] text-text-tertiary">
              {Math.round(row.elapsedMs)} ms
            </span>
          )}
        </div>
      ))}
    </div>
  )
}

function FailedAssertion({ row }: { row: RunRow }) {
  const failed = row.assertions.find((one) => !one.passed)
  if (failed === undefined) return null
  return (
    <p className="text-[11px] text-warn">
      {failed.label} — got {failed.detail}
    </p>
  )
}

export function RunNumberBox({
  label,
  value,
  onChange,
}: {
  label: string
  value: number
  onChange: (value: number) => void
}) {
  return (
    <label className="flex items-center gap-2 text-[12px] text-text-secondary">
      {label}
      <span className="w-[70px]">
        <TextInput
          type="number"
          value={String(value)}
          ariaLabel={label}
          onChange={(text) => {
            const parsed = Number(text)
            if (text !== "" && Number.isFinite(parsed)) onChange(parsed)
          }}
        />
      </span>
    </label>
  )
}
