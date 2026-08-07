import { HubRowList } from "@/components/Hub"
import { PerfChart } from "@/components/PerfChart"
import { activeInterfaces, type TimedNetSample } from "@/lib/netspeed"
import { formatKb, formatRate } from "@/lib/performance"

/**
 * What the Network Speed screen draws once samples exist: the two charts, the
 * session totals, and the per-interface breakdown.
 *
 * Split from the pane so that file stays about the recording lifecycle and
 * this one about presenting what was recorded.
 */
export function NetspeedCharts({
  live,
  latest,
  totals,
  max,
}: {
  live: TimedNetSample[]
  latest: TimedNetSample | null
  totals: { rx: number; tx: number }
  max: number
}) {
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <PerfChart
          title="Download"
          value={formatRate(latest?.downloadBytesPerSec ?? null)}
          samples={live}
          pick={(entry) => entry.downloadBytesPerSec}
          max={max}
        />
        <PerfChart
          title="Upload"
          value={formatRate(latest?.uploadBytesPerSec ?? null)}
          samples={live}
          pick={(entry) => entry.uploadBytesPerSec}
          max={max}
          tone="warn"
        />
      </div>

      <section className="rounded-lg border border-border-subtle bg-bg-surface p-3">
        <h2 className="mb-2 text-[13px] font-semibold text-text-primary">This session</h2>
        <HubRowList
          rows={[
            { label: "Downloaded", value: formatKb(totals.rx / 1024) },
            { label: "Uploaded", value: formatKb(totals.tx / 1024) },
          ]}
        />
      </section>

      <Interfaces latest={latest} />
    </div>
  )
}

/** Only the interfaces that moved something — a device reports a dozen and
    almost all of them are idle loopback and rmnet stubs. */
function Interfaces({ latest }: { latest: TimedNetSample | null }) {
  const rows = activeInterfaces(latest)
  if (rows.length === 0) return null
  return (
    <section className="rounded-lg border border-border-subtle bg-bg-surface p-3">
      <h2 className="mb-2 text-[13px] font-semibold text-text-primary">Interfaces</h2>
      <HubRowList
        rows={rows.map((entry) => ({
          label: entry.name,
          value: `↓${formatRate(entry.downloadBytesPerSec)} ↑${formatRate(entry.uploadBytesPerSec)}`,
        }))}
      />
    </section>
  )
}
