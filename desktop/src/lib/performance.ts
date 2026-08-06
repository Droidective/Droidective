/**
 * The Performance Monitor's rules.
 *
 * Record-first, as `PerformanceView` is: nothing is sampled until Record, and
 * a recording is a numbered series someone exports. This file is everything
 * done with those samples — the elapsed clock, the charts' scaling, the
 * process table's filter and sort, and both export formats. None of it needs
 * a device, so all of it is tested.
 */

import type { PerfSample } from "@/lib/wire"

/** Where a recording is. The Mac's three-way Record / Pause / Resume. */
export type PerfPhase = "idle" | "recording" | "paused"

/** The seconds between samples, fixed — what makes `elapsed` derivable. */
export const SAMPLE_INTERVAL_SECONDS = 1

/** A sample with its place in the recording. */
export interface TimedSample extends PerfSample {
  /** Seconds since Record, derived from the sample's index. */
  elapsed: number
}

/**
 * Stamps a sample with when it arrived.
 *
 * Derived from the count rather than a clock: the daemon sends no timestamp,
 * and a host clock would be a time the device never claimed. The interval is
 * fixed, so the count *is* the elapsed time — and every export says so.
 */
export function timed(sample: PerfSample, index: number): TimedSample {
  return { ...sample, elapsed: index * SAMPLE_INTERVAL_SECONDS }
}

/** "Ready" / "Recording · 01:23" — the Mac's status line, verbatim. */
export function statusText(phase: PerfPhase, samples: readonly TimedSample[]): string {
  const elapsed = samples.at(-1)?.elapsed ?? 0
  const clock = `${pad(Math.floor(elapsed / 60))}:${pad(Math.floor(elapsed) % 60)}`
  switch (phase) {
    case "recording":
      return `Recording · ${clock}`
    case "paused":
      return `Paused · ${clock}`
    default:
      return samples.length === 0 ? "Ready" : `Stopped · ${clock}`
  }
}

function pad(value: number): string {
  return String(value).padStart(2, "0")
}

/** What the Record button says next. */
export function recordLabel(phase: PerfPhase): string {
  switch (phase) {
    case "recording":
      return "Pause"
    case "paused":
      return "Resume"
    default:
      return "Record"
  }
}

/** How the process table is ordered. The Mac's segmented picker, same names. */
export type SortKey = "RAM" | "CPU" | "Name"
export const SORT_KEYS: readonly SortKey[] = ["RAM", "CPU", "Name"]

/**
 * How many samples the charts keep.
 *
 * 300 at one a second is five minutes, which is long enough to see a leak
 * develop and short enough that the array is never a memory problem of its
 * own — the thing being measured must not be the measuring.
 */
export const HISTORY_LIMIT = 300

/** The aggregate core, as `CpuCoreLoad` numbers it. */
export const ALL_CORES = -1

/** Appends a sample, dropping the oldest once the window is full. */
export function withSample(
  history: readonly PerfSample[],
  sample: PerfSample,
  limit = HISTORY_LIMIT,
): PerfSample[] {
  const next = [...history, sample]
  return next.length <= limit ? next : next.slice(next.length - limit)
}

/** Overall CPU load, or null when this sample carried no aggregate. */
export function totalCpu(sample: PerfSample): number | null {
  const all = sample.cores.find((core) => core.core === ALL_CORES)
  if (all) return all.usagePercent
  // Some devices report only per-core lines; averaging them is the same
  // number, and showing nothing would be worse than showing that.
  const individual = sample.cores.filter((core) => core.core !== ALL_CORES)
  if (individual.length === 0) return null
  return individual.reduce((sum, core) => sum + core.usagePercent, 0) / individual.length
}

/** Just the individual cores, in core order. */
export function perCore(sample: PerfSample): PerfSample["cores"] {
  return sample.cores
    .filter((core) => core.core !== ALL_CORES)
    .toSorted((left, right) => left.core - right.core)
}

/** RAM in use as a percentage, or null when the device did not say. */
export function ramPercent(sample: PerfSample): number | null {
  if (sample.ramTotalKb === null || sample.ramUsedKb === null) return null
  if (sample.ramTotalKb <= 0) return null
  return (sample.ramUsedKb / sample.ramTotalKb) * 100
}

/**
 * A series for one chart, as `[0…1]` fractions of `max`.
 *
 * Fractions rather than pixels so the same series draws at any size, and the
 * component stays about drawing.
 */
export function series<Sample extends PerfSample>(
  history: readonly Sample[],
  pick: (sample: Sample) => number | null,
  max: number,
): number[] {
  return history.map((sample) => {
    const value = pick(sample)
    if (value === null || !Number.isFinite(value) || max <= 0) return 0
    return Math.min(1, Math.max(0, value / max))
  })
}

/**
 * An SVG polyline for a series, over a 0…100 × 0…100 viewBox.
 *
 * Hand-drawn rather than a chart library: one line each for CPU, RAM and FPS
 * does not justify a dependency, and a `viewBox` scales without the component
 * having to know its own size.
 */
export function polyline(values: readonly number[]): string {
  if (values.length === 0) return ""
  if (values.length === 1) return `0,${String(round(100 - (values[0] ?? 0) * 100))} 100,${String(round(100 - (values[0] ?? 0) * 100))}`
  const step = 100 / (values.length - 1)
  return values
    .map((value, index) => `${String(round(index * step))},${String(round(100 - value * 100))}`)
    .join(" ")
}

function round(value: number): number {
  return Math.round(value * 100) / 100
}

/** The highest value in a series, for a chart's own scale. */
export function peak<Sample extends PerfSample>(
  history: readonly Sample[],
  pick: (sample: Sample) => number | null,
): number {
  let highest = 0
  for (const sample of history) {
    const value = pick(sample)
    if (value !== null && Number.isFinite(value) && value > highest) highest = value
  }
  return highest
}

/** "1.2 GB" / "340 MB" — kilobytes as the device reports them. */
export function formatKb(kb: number | null): string {
  if (kb === null || !Number.isFinite(kb) || kb <= 0) return "—"
  const units = ["KB", "MB", "GB", "TB"] as const
  let value = kb
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  const rounded = value < 100 ? Math.round(value * 10) / 10 : Math.round(value)
  return `${String(rounded)} ${units[unit] ?? "KB"}`
}

/** "12.3 MB/s" / "480 KB/s" — a throughput, or a dash. */
export function formatRate(bytesPerSec: number | null): string {
  if (bytesPerSec === null || !Number.isFinite(bytesPerSec) || bytesPerSec < 0) return "—"
  if (bytesPerSec < 1024) return `${String(Math.round(bytesPerSec))} B/s`
  return `${formatKb(bytesPerSec / 1024)}/s`
}

/** One decimal, or a dash when the device did not answer. */
export function formatNumber(value: number | null, suffix = ""): string {
  if (value === null || !Number.isFinite(value)) return "—"
  return `${String(Math.round(value * 10) / 10)}${suffix}`
}

/**
 * The process table: the rows matching `filter`, in `sort` order.
 *
 * RAM first by default, which is what the Mac defaults to — a leak is the
 * thing people open this for.
 */
export function tableProcesses(
  sample: PerfSample | null,
  filter: string,
  sort: SortKey,
): PerfSample["processes"] {
  if (sample === null) return []
  const needle = filter.toLowerCase().trim()
  const rows = sample.processes.filter(
    (process) => needle === "" || process.name.toLowerCase().includes(needle),
  )
  return rows.toSorted((left, right) => {
    if (sort === "Name") return left.name.localeCompare(right.name)
    if (sort === "CPU") return (right.cpuPercent ?? 0) - (left.cpuPercent ?? 0)
    return (right.pssKb ?? 0) - (left.pssKb ?? 0)
  })
}

const CSV_COLUMNS = [
  "elapsedSeconds",
  "cpuPercent",
  "ramUsedKb",
  "ramTotalKb",
  "fps",
  "jankPercent",
  "appPssKb",
  "downloadBytesPerSec",
  "uploadBytesPerSec",
] as const

/**
 * A recording as CSV.
 *
 * Elapsed seconds rather than a wall clock: the daemon sends no timestamp, and
 * inventing one here would be a time the device never claimed.
 */
export function toCsv(history: readonly TimedSample[]): string {
  const rows = history.map((sample) =>
    [
      sample.elapsed,
      cell(totalCpu(sample)),
      cell(sample.ramUsedKb),
      cell(sample.ramTotalKb),
      cell(sample.appFps),
      cell(sample.appJankPercent),
      cell(sample.appPssKb),
      cell(sample.downloadBytesPerSec),
      cell(sample.uploadBytesPerSec),
    ].join(","),
  )
  return [`# one sample every ${String(SAMPLE_INTERVAL_SECONDS)}s`, CSV_COLUMNS.join(","), ...rows].join("\n")
}

/**
 * The same recording as JSON, which is the other half of the Mac's export.
 *
 * Both formats, always: the CSV is for a spreadsheet and the JSON keeps the
 * per-process rows a CSV row cannot hold.
 */
export function toJson(
  history: readonly TimedSample[],
  context: { serial: string; packageId: string | null },
): string {
  return JSON.stringify(
    {
      device: context.serial,
      package: context.packageId,
      intervalSeconds: SAMPLE_INTERVAL_SECONDS,
      samples: history,
    },
    null,
    2,
  )
}

function cell(value: number | null): string {
  if (value === null || !Number.isFinite(value)) return ""
  return String(Math.round(value * 100) / 100)
}
