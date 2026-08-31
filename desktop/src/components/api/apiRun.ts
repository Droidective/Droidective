import { newId } from "@/lib/api/defaults"
import type { ApiCollection, AuthSpec, SavedRequest } from "@/lib/api/model"
import {
  effectiveIterations,
  flatten,
  shouldStop,
  summarise,
  type RunOptions,
  type RunRow,
  type RunSummary,
} from "@/lib/api/runner"
import type { VariableScope } from "@/lib/api/variables"
import { inheritedAuth } from "@/lib/api/workspace"
import { apiSend, asDaemonError } from "@/lib/daemon"

/**
 * The collection run itself.
 *
 * The one deliberate difference from the Mac's `ApiRunner`: the loop lives on
 * this side rather than behind a route, because the requests it walks are
 * already here. That is what makes a row appear the moment it lands and Stop
 * instant — a run route would have to grow a stream to say as much. What it
 * runs and when it stops is `lib/api/runner.ts`, and tested.
 *
 * `isCurrent` is how Stop reaches it: the sheet bumps a generation, and the
 * loop notices between requests. A request already on the wire is left to
 * finish rather than torn down halfway, which is what the Mac's runner does
 * when its task is cancelled between steps.
 */
export async function performRun({
  collection,
  options,
  scope,
  isCurrent,
  onRow,
}: {
  collection: ApiCollection
  options: RunOptions
  scope: VariableScope
  isCurrent: () => boolean
  onRow: (rows: RunRow[]) => void
}): Promise<RunSummary> {
  const collected: RunRow[] = []
  const started = performance.now()
  const plan = flatten(collection.items)
  const auth = inheritedAuth(collection)
  let cancelled = false

  iterations: for (
    let iteration = 1;
    iteration <= effectiveIterations(options);
    iteration += 1
  ) {
    for (const step of plan) {
      if (!isCurrent()) {
        cancelled = true
        break iterations
      }
      if (options.delayMs > 0 && collected.length > 0) await pause(options.delayMs)
      const row = await runOne(step.request, step.path, iteration, scope, auth)
      if (!isCurrent()) {
        cancelled = true
        break iterations
      }
      collected.push(row)
      onRow([...collected])
      if (shouldStop(options, row)) break iterations
    }
  }

  return summarise(collected, performance.now() - started, cancelled)
}

function pause(ms: number): Promise<void> {
  return new Promise((resume) => {
    setTimeout(resume, ms)
  })
}

/**
 * One request, as a row.
 *
 * No `sendId` is passed: a run stops by leaving the loop, so there is nothing
 * for a cancel route to reach.
 */
async function runOne(
  request: SavedRequest,
  path: string[],
  iteration: number,
  scope: VariableScope,
  inherited: AuthSpec | null,
): Promise<RunRow> {
  const base = { id: newId(), iteration, name: request.name, path, method: request.method }
  try {
    const answer = await apiSend({ request, scope, inheritedAuth: inherited })
    return {
      ...base,
      url: answer.preparedURL === "" ? request.url : answer.preparedURL,
      statusCode: answer.statusCode,
      elapsedMs: answer.elapsedMs,
      errorText: null,
      assertions: answer.assertions,
    }
  } catch (thrown) {
    return {
      ...base,
      url: request.url,
      statusCode: null,
      elapsedMs: null,
      errorText: asDaemonError(thrown).message,
      assertions: [],
    }
  }
}
