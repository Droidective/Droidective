import { useCallback, useRef, useState } from "react"

import { ApiSheet } from "@/components/api/ApiKit"
import { ApiRunResults, RunNumberBox } from "@/components/api/ApiRunResults"
import { Button, Switch } from "@/components/Controls"
import type { ApiCollection } from "@/lib/api/model"
import { performRun } from "@/components/api/apiRun"
import {
  DEFAULT_RUN_OPTIONS,
  headline,
  type RunOptions,
  type RunRow,
  type RunSummary,
} from "@/lib/api/runner"
import { requestCount } from "@/lib/api/tree"
import type { VariableScope } from "@/lib/api/variables"
import { cn } from "@/lib/cn"

/**
 * The collection runner — the Mac's `RunnerSheet`.
 *
 * The loop is here rather than behind a route, which is the one deliberate
 * difference from the Mac's `ApiRunner`: the requests it walks are already on
 * this side, so running them here makes each row appear as it lands and makes
 * Stop instant. What decides *what* runs is `lib/api/runner.ts`, and tested.
 */
export function ApiRunnerSheet({
  collection,
  scope,
  onDismiss,
}: {
  collection: ApiCollection | undefined
  scope: VariableScope
  onDismiss: () => void
}) {
  const [options, setOptions] = useState<RunOptions>(DEFAULT_RUN_OPTIONS)
  const [rows, setRows] = useState<RunRow[]>([])
  const [summary, setSummary] = useState<RunSummary | null>(null)
  const [running, setRunning] = useState(false)
  /** Bumped to stop a run; the loop checks it between requests. */
  const generation = useRef(0)

  const total = collection === undefined ? 0 : requestCount(collection.items)

  const run = useCallback(() => {
    if (collection === undefined) return
    const mine = generation.current + 1
    generation.current = mine
    setRows([])
    setSummary(null)
    setRunning(true)
    void performRun({
      collection,
      options,
      scope,
      isCurrent: () => generation.current === mine,
      onRow: setRows,
    }).then((finished) => {
      if (generation.current !== mine) return
      setSummary(finished)
      setRunning(false)
    })
  }, [collection, options, scope])

  const stop = useCallback(() => {
    generation.current += 1
    setRunning(false)
  }, [])

  return (
    <ApiSheet
      title={`Run ${collection?.name ?? "Collection"}`}
      width={560}
      onDismiss={onDismiss}
      footer={
        <>
          {summary === null ? null : (
            <span
              className={cn(
                "mr-auto text-[12px]",
                summary.failed === 0 ? "text-accent" : "text-warn",
              )}
            >
              {headline(summary, rows.length)}
            </span>
          )}
          <Button onClick={onDismiss}>Close</Button>
          {running ? (
            <Button onClick={stop}>Stop</Button>
          ) : (
            <Button tone="primary" onClick={run} disabled={total === 0}>
              Run
            </Button>
          )}
        </>
      }
    >
      <p className="text-[12px] text-text-secondary">
        {total} requests, sent in order with the active environment.
      </p>
      <OptionsRow options={options} onChange={setOptions} />
      <div className="h-px bg-border-subtle" />
      <ApiRunResults rows={rows} running={running} />
    </ApiSheet>
  )
}

function OptionsRow({
  options,
  onChange,
}: {
  options: RunOptions
  onChange: (change: (options: RunOptions) => RunOptions) => void
}) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <RunNumberBox
        label="Iterations"
        value={options.iterations}
        onChange={(iterations) => {
          onChange((was) => ({ ...was, iterations }))
        }}
      />
      <RunNumberBox
        label="Delay (ms)"
        value={options.delayMs}
        onChange={(delayMs) => {
          onChange((was) => ({ ...was, delayMs }))
        }}
      />
      <Switch
        checked={options.stopOnFailure}
        label="Stop on first failure"
        onChange={(stopOnFailure) => {
          onChange((was) => ({ ...was, stopOnFailure }))
        }}
      />
    </div>
  )
}
