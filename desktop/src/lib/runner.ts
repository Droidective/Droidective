import { summarise } from "@/lib/targets"
import type { FieldValue, RunResponse } from "@/lib/wire"

/**
 * Running one feature across one or more devices, as a single answer.
 *
 * The `run` function is injected rather than imported so this is testable
 * without a daemon — the `ProcessRunning` seam, in miniature. The rules worth
 * defending live here rather than in a comment inside a component:
 *
 * - **Sequential.** These are adb calls against one shared server, and the
 *   Mac's own fan-out loop is sequential too.
 * - **One device keeps its reply intact**, extras included. That is most of the
 *   app, and it must not grow a summary it never had.
 * - **Several collapse**, and drop the extras: a copyable value from whichever
 *   device answered first would be a value for a device nobody asked about.
 */
export interface RunRequest {
  featureId: string
  serials: readonly string[]
  platform: string
  fields: Record<string, FieldValue> | undefined
}

export type RunOne = (args: {
  featureId: string
  serial: string
  platform: string
  fields?: Record<string, FieldValue>
}) => Promise<RunResponse>

export async function runOnTargets(
  run: RunOne,
  request: RunRequest,
): Promise<RunResponse | null> {
  const outcomes: { serial: string; ok: boolean; message: string; result: RunResponse }[] = []
  for (const serial of request.serials) {
    const result = await run({
      featureId: request.featureId,
      serial,
      platform: request.platform,
      ...(request.fields ? { fields: request.fields } : {}),
    })
    outcomes.push({ serial, ok: result.ok, message: result.message, result })
  }
  const first = outcomes[0]
  // No targets at all: nothing ran, so there is nothing to report. The caller's
  // Run button is disabled in that state; this is the belt as well as braces.
  if (first === undefined) return null
  if (outcomes.length === 1) return first.result
  const summary = summarise(outcomes)
  return {
    ok: summary.ok,
    message: summary.message,
    copyText: null,
    revealPath: null,
    // One device needing the keyboard is the whole fan-out needing it: the
    // instruction is the same and it only has to be said once.
    needsAdbKeyboard: outcomes.some((outcome) => outcome.result.needsAdbKeyboard),
  }
}
