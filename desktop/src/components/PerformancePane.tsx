import { useState } from "react"
import { Circle, Pause, Play, Square, Upload } from "lucide-react"
import { useNotifications } from "@/hooks/useNotifications"
import { ConfirmDialog, NoDevice } from "@/components/screen"
import { Banner, Button, Switch } from "@/components/Controls"
import { PerfCharts, PerfProcessCard } from "@/components/PerfCharts"
import { usePerformance, type Performance } from "@/hooks/usePerformance"
import { writeRecording } from "@/lib/perfexport"
import {
  formatKb,
  formatNumber,
  formatRate,
  recordLabel,
  statusText,
  totalCpu,
  type TimedSample,
} from "@/lib/performance"
import type { Device } from "@/lib/wire"

/**
 * CPU, RAM and FPS over a recording — the Mac's Performance Monitor.
 *
 * Record-first, exactly as `PerformanceView` is: nothing is sampled until
 * Record, one button cycles Record → Pause → Resume, Stop offers to export
 * first, and an export writes JSON *and* CSV. The app chosen in Apps is what
 * FPS and app memory are measured for.
 */
export function PerformancePane({
  device,
  packageId,
}: {
  device: Device | null
  packageId: string | null
}) {
  const [processes, setProcesses] = useState(false)
  const perf = usePerformance({ serial: device?.serial ?? null, packageId, processes })
  const [confirmingStop, setConfirmingStop] = useState(false)
  const { show } = useNotifications()

  if (!device) return <NoDevice feature="performance" title="Performance" />

  const exportRecording = () => {
    writeRecording(perf.samples, { serial: device.serial, packageId }).then(show, () => {
      /* exportBoth never rejects; it reports through the toast. */
    })
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <Controls
        perf={perf}
        processes={processes}
        onProcesses={setProcesses}
        packageId={packageId}
        onExport={exportRecording}
        onStop={() => {
          if (perf.samples.length === 0) {
            perf.stop()
            return
          }
          setConfirmingStop(true)
        }}
      />

      {confirmingStop ? (
        <ConfirmDialog
          title="Export this recording before stopping?"
          message={`${String(perf.samples.length)} samples captured — exported as JSON + CSV.`}
          confirmLabel="Stop without exporting"
          extraLabel="Export…"
          onExtra={() => {
            setConfirmingStop(false)
            exportRecording()
            perf.stop()
          }}
          onConfirm={() => {
            setConfirmingStop(false)
            perf.stop()
          }}
          onCancel={() => {
            setConfirmingStop(false)
          }}
        />
      ) : null}

      <Notices perf={perf} />

      {perf.samples.length === 0 ? (
        <p className="flex min-h-0 flex-1 items-center justify-center px-8 text-center text-text-tertiary">
          Nothing recorded yet. Press Record to start sampling.
        </p>
      ) : (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-3">
          <PerfCharts samples={perf.samples} packageId={packageId} />
          <PerfProcessCard latest={perf.latest} enabled={processes} />
        </div>
      )}
    </div>
  )
}

function Controls({
  perf,
  processes,
  onProcesses,
  packageId,
  onExport,
  onStop,
}: {
  perf: Performance
  processes: boolean
  onProcesses: (on: boolean) => void
  packageId: string | null
  onExport: () => void
  onStop: () => void
}) {
  const recording = perf.phase === "recording"
  return (
    <div className="flex shrink-0 flex-wrap items-center gap-2.5 border-b border-border-subtle bg-bg-chrome px-3 py-2">
      <Button
        tone="danger"
        onClick={perf.toggleRecord}
        title="Start, pause, or resume sampling"
      >
        <span className="flex min-w-[72px] items-center justify-center gap-1.5">
          {recording ? (
            <Pause size={11} />
          ) : perf.phase === "paused" ? (
            <Play size={11} />
          ) : (
            <Circle size={11} className="fill-white" />
          )}
          {recordLabel(perf.phase)}
        </span>
      </Button>

      <Button onClick={onStop} disabled={perf.phase === "idle"} title="Stop recording">
        <Square size={11} />
      </Button>

      <Button
        tone="primary"
        onClick={onExport}
        disabled={perf.samples.length === 0}
        title="Export the recording as JSON + CSV"
      >
        <span className="flex items-center gap-1.5">
          <Upload size={12} />
          Export
        </span>
      </Button>

      {/* Two extra dumpsys calls a sample, so it is asked for rather than
          assumed: leaving it on would show up in the numbers being measured. */}
      <Switch checked={processes} onChange={onProcesses} label="Per-process" />

      <span className="flex-1" />

      {perf.latest === null ? null : <SummaryChips latest={perf.latest} packageId={packageId} />}
      <span
        className={
          recording
            ? "tabular-nums text-text-primary"
            : "tabular-nums text-text-tertiary"
        }
      >
        {statusText(perf.phase, perf.samples)}
      </span>
    </div>
  )
}

/** The Mac's four capsules: CPU, RAM, NET, and FPS once an app is picked. */
function SummaryChips({ latest, packageId }: { latest: TimedSample; packageId: string | null }) {
  return (
    <span className="flex flex-wrap items-center gap-1.5">
      <Chip label="CPU" value={formatNumber(totalCpu(latest), "%")} />
      <Chip label="RAM" value={formatKb(latest.ramUsedKb)} />
      <Chip
        label="NET"
        value={`↓${formatRate(latest.downloadBytesPerSec)} ↑${formatRate(latest.uploadBytesPerSec)}`}
      />
      {packageId === null ? null : (
        <Chip label="FPS" value={formatNumber(latest.appFps)} />
      )}
    </span>
  )
}

function Chip({ label, value }: { label: string; value: string }) {
  return (
    <span className="flex items-center gap-1 rounded-full bg-white/[0.07] px-2 py-0.5">
      <span className="text-[10px] font-semibold uppercase tracking-[0.04em] text-accent">
        {label}
      </span>
      <span className="tabular-nums text-[11.5px] text-text-primary">{value}</span>
    </span>
  )
}

/**
 * The stream's own states.
 *
 * An export's result goes to a toast; what is left is what is *about the
 * recording* rather than about something that just happened.
 */
function Notices({ perf }: { perf: Performance }) {
  if (perf.error === null && perf.dropped === 0) return null
  return (
    <div className="flex shrink-0 flex-col gap-2 px-3 pt-3">
      {perf.error === null ? null : <Banner tone="error">{perf.error.message}</Banner>}
      {perf.dropped === 0 ? null : (
        // Never swallowed: a chart with a silent gap claims a continuity it
        // does not have, and the elapsed clock would understate the run.
        <Banner tone="warn">{perf.dropped} samples were dropped — the charts have a gap.</Banner>
      )}
    </div>
  )
}
