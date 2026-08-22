import { useEffect, useRef, useState } from "react"
import { MemoryStick } from "lucide-react"
import { Banner } from "@/components/Controls"
import { HubRowList } from "@/components/Hub"
import { NoBundle } from "@/components/NoBundle"
import { PerfChart } from "@/components/PerfChart"
import { NoDevice } from "@/components/screen"
import { asDaemonError, meminfo } from "@/lib/daemon"
import { formatKb } from "@/lib/performance"
import type { DaemonError, Device, MemInfoResponse } from "@/lib/wire"

/** ~3 minutes of 2s samples, as the Mac's window is. */
const WINDOW = 90
const INTERVAL_MS = 2000

interface Reading {
  elapsed: number
  pssKb: number
}

/**
 * Live memory for the chosen app — the Mac's `MeminfoView`.
 *
 * Polls every two seconds, keeps three minutes of Total PSS on a chart, and
 * lists `dumpsys meminfo`'s summary block underneath in the order it printed.
 * Polling stops when the pane unmounts; a stopped app says so rather than
 * charting zeroes.
 */
export function MeminfoPane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  const [info, setInfo] = useState<MemInfoResponse | null>(null)
  const [history, setHistory] = useState<Reading[]>([])
  const [error, setError] = useState<DaemonError | null>(null)
  const samples = useRef(0)

  const serial = device?.serial ?? null
  useEffect(() => {
    setInfo(null)
    setHistory([])
    samples.current = 0
    if (serial === null || packageId === null) return

    let live = true
    const read = async () => {
      try {
        const next = await meminfo(serial, packageId)
        if (!live) return
        setInfo(next)
        setError(null)
        if (next.totalPssKb !== null) {
          const elapsed = samples.current * (INTERVAL_MS / 1000)
          samples.current += 1
          setHistory((current) =>
            [...current, { elapsed, pssKb: next.totalPssKb ?? 0 }].slice(-WINDOW),
          )
        }
      } catch (thrown) {
        if (live) setError(asDaemonError(thrown))
      }
    }
    void read()
    const timer = globalThis.setInterval(() => void read(), INTERVAL_MS)
    return () => {
      live = false
      globalThis.clearInterval(timer)
    }
  }, [packageId, serial])

  if (!device) return <NoDevice feature="meminfo" title="Memory Usage" />
  if (packageId === null) return <NoBundle what="watch its memory usage" />

  if (error !== null) {
    return (
      <div className="p-5">
        <Banner tone="error">{error.message}</Banner>
      </div>
    )
  }
  if (info === null) return <p className="p-5 text-text-tertiary">Reading memory…</p>
  if (!info.running) return <NotRunning />

  const peak = history.reduce((highest, row) => Math.max(highest, row.pssKb), 0)

  return (
    <div className="flex h-full flex-col overflow-y-auto">
      <div className="mx-auto flex w-full max-w-[640px] flex-col gap-4 p-5">
        <div className="flex items-baseline gap-7">
          <Stat label="Total PSS" value={formatKb(info.totalPssKb)} big />
          {peak > 0 ? <Stat label="Peak" value={formatKb(peak)} /> : null}
        </div>

        <PerfChart
          title="Total PSS over time"
          value={formatKb(info.totalPssKb)}
          samples={history}
          pick={(row) => row.pssKb}
          // Headroom over the peak so the line does not sit on the ceiling,
          // and a floor so an idle app is not drawn as a full-scale spike.
          max={Math.max(peak * 1.2, 1)}
        />

        {info.summary.length === 0 ? null : (
          <section className="rounded-xl border border-border-subtle bg-bg-surface p-4">
            <h2 className="mb-3 text-[13px] font-semibold text-text-primary">Summary</h2>
            <HubRowList
              rows={info.summary.map((row) => ({
                label: row.key,
                value: formatKb(Number(row.value)),
              }))}
            />
          </section>
        )}

        <p className="text-[11.5px] text-text-tertiary">Refreshes every 2 seconds.</p>
      </div>
    </div>
  )
}

function Stat({ label, value, big = false }: { label: string; value: string; big?: boolean }) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-[11.5px] text-text-tertiary">{label}</span>
      <span
        className={
          big
            ? "text-[30px] font-semibold tabular-nums text-text-primary"
            : "text-[17px] font-medium tabular-nums text-text-primary"
        }
      >
        {value}
      </span>
    </div>
  )
}

function NotRunning() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <MemoryStick size={26} className="text-text-tertiary" />
      <h2 className="text-[15px] font-medium text-text-primary">App not running</h2>
      <p className="max-w-sm text-text-secondary">
        Open the app on the device to see live memory.
      </p>
    </div>
  )
}
