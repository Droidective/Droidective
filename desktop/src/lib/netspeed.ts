/**
 * The Network Speed screen's rules.
 *
 * Two independent states, as `NetworkView` has: **live** means the sampler is
 * running and the chart is rolling, **recording** means those samples are also
 * being kept for export. You can watch traffic without recording it, and the
 * Mac makes that split because watching is the common case and an accidental
 * unexported recording is the annoying one.
 *
 * None of this needs a device, so all of it is tested.
 */

import type { NetSample } from "@/lib/wire"

/** A sample with its place on the timeline. */
export interface TimedNetSample extends NetSample {
  /** Seconds since the sampler started. */
  elapsed: number
}

/** The seconds between samples, fixed by the daemon's poll. */
export const SAMPLE_INTERVAL_SECONDS = 1

/** The rolling window the chart draws — two minutes, as the Mac's is. */
export const CHART_WINDOW = 120

/**
 * How many samples a recording keeps.
 *
 * The Mac caps at 5000, which is about 83 minutes. Bounded is the point: a
 * monitor that grows without limit eventually becomes the thing it is
 * measuring.
 */
export const MAX_SAMPLES = 5000

export function timed(sample: NetSample, index: number): TimedNetSample {
  return { ...sample, elapsed: index * SAMPLE_INTERVAL_SECONDS }
}

/** Appends, dropping the oldest once the window is full. */
export function withSample<Sample>(
  history: readonly Sample[],
  sample: Sample,
  limit: number,
): Sample[] {
  const next = [...history, sample]
  return next.length <= limit ? next : next.slice(next.length - limit)
}

/**
 * Bytes moved since the sampler started.
 *
 * Differenced against the *first* sample rather than accumulated per-tick:
 * the device reports counters since boot, and a subscribe that begins
 * mid-session would otherwise report the device's lifetime traffic as this
 * session's. Counters that went backwards — a reboot — read as zero rather
 * than as a huge negative.
 */
export function sessionTotals(history: readonly NetSample[]): { rx: number; tx: number } {
  const first = history.at(0)
  const last = history.at(-1)
  if (first === undefined || last === undefined) return { rx: 0, tx: 0 }
  return {
    rx: Math.max(0, last.totalRxBytes - first.totalRxBytes),
    tx: Math.max(0, last.totalTxBytes - first.totalTxBytes),
  }
}

/** "Live · 01:23" / "Recording · 01:23" / "Idle" — the Mac's status line. */
export function statusText(live: boolean, recording: boolean, elapsed: number): string {
  if (!live) return "Idle"
  const clock = `${pad(Math.floor(elapsed / 60))}:${pad(Math.floor(elapsed) % 60)}`
  return `${recording ? "Recording" : "Live"} · ${clock}`
}

function pad(value: number): string {
  return String(value).padStart(2, "0")
}

/**
 * A chart's top, given what has been seen.
 *
 * Headroom over the peak so the line does not sit on the ceiling, and a floor
 * so an idle interface is not drawn as a full-scale spike — the same reasoning
 * the Mac's auto-scaling chart uses.
 */
export function chartMax(history: readonly NetSample[]): number {
  let peak = 0
  for (const sample of history) {
    peak = Math.max(peak, sample.downloadBytesPerSec, sample.uploadBytesPerSec)
  }
  // 64 KB/s floor: below that the noise of a mostly-idle device would fill
  // the chart.
  return Math.max(peak * 1.2, 64 * 1024)
}

/** The interfaces worth listing: the ones that actually moved something. */
export function activeInterfaces(sample: NetSample | null): NetSample["interfaces"] {
  if (sample === null) return []
  return sample.interfaces.filter(
    (entry) => entry.downloadBytesPerSec > 0 || entry.uploadBytesPerSec > 0,
  )
}

/** A recording as JSON, with the context needed to read it later. */
export function toJson(history: readonly TimedNetSample[], serial: string): string {
  return JSON.stringify(
    {
      serial,
      intervalSeconds: SAMPLE_INTERVAL_SECONDS,
      samples: history.map((sample) => ({
        elapsed: sample.elapsed,
        downloadBytesPerSec: sample.downloadBytesPerSec,
        uploadBytesPerSec: sample.uploadBytesPerSec,
        totalRxBytes: sample.totalRxBytes,
        totalTxBytes: sample.totalTxBytes,
        interfaces: sample.interfaces,
      })),
    },
    null,
    2,
  )
}

/**
 * A recording as CSV.
 *
 * The device-wide figures only: a per-interface breakdown is a second
 * dimension a CSV row cannot hold, and it is in the JSON beside it.
 */
export function toCsv(history: readonly TimedNetSample[]): string {
  const rows = ["elapsed_s,download_bps,upload_bps,total_rx_bytes,total_tx_bytes"]
  for (const sample of history) {
    rows.push(
      [
        sample.elapsed,
        Math.round(sample.downloadBytesPerSec),
        Math.round(sample.uploadBytesPerSec),
        sample.totalRxBytes,
        sample.totalTxBytes,
      ].join(","),
    )
  }
  return `${rows.join("\n")}\n`
}
