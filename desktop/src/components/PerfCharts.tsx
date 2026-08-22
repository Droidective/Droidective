import { useState } from "react"
import { PerfChart } from "@/components/PerfChart"
import { Select, TextInput } from "@/components/Controls"
import {
  formatKb,
  formatNumber,
  formatRate,
  SORT_KEYS,
  tableProcesses,
  totalCpu,
  type SortKey,
  type TimedSample,
} from "@/lib/performance"

/**
 * The cards, in the order `PerformanceView` stacks them: CPU, system RAM, app
 * memory, network, FPS, processes. The app cards appear only when an app has
 * been picked, because that is the only time there is anything in them.
 */
export function PerfCharts({
  samples,
  packageId,
}: {
  samples: readonly TimedSample[]
  packageId: string | null
}) {
  const latest = samples.at(-1) ?? null
  if (latest === null) return null
  return (
    <>
      <PerfChart
        title="CPU"
        value={formatNumber(totalCpu(latest), "%")}
        samples={samples}
        pick={totalCpu}
        max={100}
      />
      <PerfChart
        title="System RAM"
        value={`${formatKb(latest.ramUsedKb)} of ${formatKb(latest.ramTotalKb)}`}
        samples={samples}
        pick={(sample) => sample.ramUsedKb}
        max={latest.ramTotalKb ?? 0}
        tone="warn"
      />
      {packageId === null ? null : (
        <PerfChart
          title="App memory"
          value={formatKb(latest.appPssKb)}
          samples={samples}
          pick={(sample) => sample.appPssKb}
          max={peakOf(samples, (sample) => sample.appPssKb)}
          tone="warn"
        />
      )}
      <PerfChart
        title="Network"
        value={`↓${formatRate(latest.downloadBytesPerSec)} ↑${formatRate(latest.uploadBytesPerSec)}`}
        samples={samples}
        pick={(sample) => sample.downloadBytesPerSec}
        max={peakOf(samples, (sample) => sample.downloadBytesPerSec)}
      />
      {packageId === null ? null : (
        <PerfChart
          title="FPS"
          value={formatNumber(latest.appFps, " fps")}
          samples={samples}
          pick={(sample) => sample.appFps}
          // 60 is the deadline almost every Android surface is drawn to, so it
          // is the line worth seeing a dip below.
          max={60}
          tone="danger"
        />
      )}
    </>
  )
}

/** A chart with no fixed ceiling scales to its own tallest sample. */
function peakOf(
  samples: readonly TimedSample[],
  pick: (sample: TimedSample) => number | null,
): number {
  let highest = 0
  for (const sample of samples) {
    const value = pick(sample)
    if (value !== null && Number.isFinite(value) && value > highest) highest = value
  }
  return highest
}

/**
 * The process card — "N of M", a name filter and the Mac's segmented sort.
 *
 * Per-process figures cost two extra `dumpsys` calls a sample, so they arrive
 * only when asked for; the empty line says so rather than looking broken.
 */
export function PerfProcessCard({
  latest,
  enabled,
}: {
  latest: TimedSample | null
  enabled: boolean
}) {
  const [filter, setFilter] = useState("")
  const [sort, setSort] = useState<SortKey>("RAM")
  const all = latest?.processes ?? []
  const rows = tableProcesses(latest, filter, sort)

  return (
    <section className="rounded-lg border border-border-subtle bg-bg-surface p-3">
      <header className="mb-2 flex items-baseline justify-between gap-2">
        <h3 className="text-[10.5px] uppercase tracking-[0.06em] text-text-tertiary">Processes</h3>
        <span className="text-[11.5px] text-text-tertiary">
          {rows.length} of {all.length}
        </span>
      </header>

      <div className="mb-2 flex items-center gap-2">
        <span className="min-w-0 flex-1">
          <TextInput value={filter} onChange={setFilter} placeholder="Filter by name…" />
        </span>
        <span className="w-[110px]">
          <Select
            value={sort}
            options={SORT_KEYS.map((key) => ({ value: key, label: key }))}
            onChange={(value) => {
              setSort(value as SortKey)
            }}
          />
        </span>
      </div>

      <div className="flex gap-3 border-b border-border-subtle pb-1 text-[10.5px] uppercase tracking-[0.06em] text-text-tertiary">
        <span className="min-w-0 flex-1">Process</span>
        <span className="w-16 text-right">PID</span>
        <span className="w-14 text-right">CPU</span>
        <span className="w-20 text-right">RAM</span>
      </div>

      {rows.length === 0 ? (
        <p className="py-2 text-text-tertiary">
          {enabled
            ? all.length === 0
              ? "Per-process data appears while recording."
              : "No processes match the filter."
            : "Turn on Per-process to collect this."}
        </p>
      ) : (
        rows.map((process) => (
          <div key={process.pid} className="flex gap-3 py-0.5 text-[12px]">
            <span className="min-w-0 flex-1 truncate font-mono text-text-primary">
              {process.name}
            </span>
            <span className="w-16 text-right tabular-nums text-text-tertiary">{process.pid}</span>
            <span className="w-14 text-right tabular-nums text-text-secondary">
              {formatNumber(process.cpuPercent, "%")}
            </span>
            <span className="w-20 text-right tabular-nums text-text-secondary">
              {formatKb(process.pssKb)}
            </span>
          </div>
        ))
      )}
    </section>
  )
}
