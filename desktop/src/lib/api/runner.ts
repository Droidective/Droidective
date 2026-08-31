/**
 * The collection runner's decisions, without the sending.
 *
 * On the Mac `ApiRunner` lives in ADBKit because the whole feature does. Here
 * the seam is one send, so the walk stays on this side and each request goes
 * through `/v1/api/send` in turn. Same sequential order, same scope, same
 * stop-on-failure — and because the loop is here, a row appears the moment it
 * lands and Stop is instant rather than a second route.
 *
 * Everything that decides *what* runs is in this file and tested; the hook
 * around it only awaits.
 */

import { allRequests } from "@/lib/api/tree"
import type { ApiItem, HttpMethod, SavedRequest } from "@/lib/api/model"

export interface RunOptions {
  iterations: number
  /** Pause between requests, in milliseconds. */
  delayMs: number
  stopOnFailure: boolean
}

export const DEFAULT_RUN_OPTIONS: RunOptions = { iterations: 1, delayMs: 0, stopOnFailure: false }

/** `RunOptions.effectiveIterations` — at least one, at most a hundred. */
export function effectiveIterations(options: RunOptions): number {
  if (!Number.isFinite(options.iterations)) return 1
  return Math.max(1, Math.min(Math.trunc(options.iterations), 100))
}

export interface RunStep {
  request: SavedRequest
  /** Folder names leading to the request. */
  path: string[]
}

export interface AssertionOutcome {
  id: string
  label: string
  passed: boolean
  detail: string
}

export interface RunRow {
  id: string
  iteration: number
  name: string
  path: string[]
  method: HttpMethod
  url: string
  statusCode: number | null
  elapsedMs: number | null
  errorText: string | null
  assertions: AssertionOutcome[]
}

/** The requests to send, depth-first, with the folders that lead to each. */
export function flatten(items: ApiItem[], prefix: string[] = []): RunStep[] {
  const out: RunStep[] = []
  for (const item of items) {
    if (item.kind === "request") out.push({ request: item.request, path: prefix })
    else out.push(...flatten(item.folder.items, [...prefix, item.folder.name]))
  }
  return out
}

/**
 * A row passes when it got a 2xx and every assertion held.
 *
 * A request with no assertions is judged on its status alone — `RunResult.passed`.
 */
export function rowPassed(row: RunRow): boolean {
  if (row.errorText !== null) return false
  if (row.statusCode === null || row.statusCode < 200 || row.statusCode >= 300) return false
  return row.assertions.every((assertion) => assertion.passed)
}

export interface RunSummary {
  passed: number
  failed: number
  assertions: number
  totalMs: number
  cancelled: boolean
}

export function summarise(rows: RunRow[], totalMs: number, cancelled: boolean): RunSummary {
  const passed = rows.filter((row) => rowPassed(row)).length
  return {
    passed,
    failed: rows.length - passed,
    assertions: rows.reduce((count, row) => count + row.assertions.length, 0),
    totalMs,
    cancelled,
  }
}

/** `RunSummary.headline`, word for word. */
export function headline(summary: RunSummary, requests: number): string {
  const plural = summary.assertions === 1 ? "" : "s"
  return (
    `${summary.passed}/${requests} passed · ${summary.assertions} assertion${plural}` +
    ` · ${(summary.totalMs / 1000).toFixed(1)}s`
  )
}

/**
 * Whether the run should stop after this row.
 *
 * Its own function because the rule reads backwards otherwise: `stopOnFailure`
 * stops on a row that did *not* pass, and "not passed" is more than a non-2xx.
 */
export function shouldStop(options: RunOptions, row: RunRow): boolean {
  return options.stopOnFailure && !rowPassed(row)
}

/** How many requests a collection would send, for the sheet's own sentence. */
export function plannedCount(items: ApiItem[], options: RunOptions): number {
  return allRequests(items).length * effectiveIterations(options)
}
