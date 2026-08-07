import { Circle, Square, Upload } from "lucide-react"
import { Button } from "@/components/Controls"
import type { useNetspeed } from "@/hooks/useNetspeed"
import { statusText, type TimedNetSample } from "@/lib/netspeed"
import { formatRate } from "@/lib/performance"

/** Record / Stop, Export, the live chips, and the status line. */
export function NetspeedToolbar({
  net,
  latest,
  onExport,
  onStop,
}: {
  net: ReturnType<typeof useNetspeed>
  latest: TimedNetSample | null
  onExport: () => void
  onStop: () => void
}) {
  return (
    <div className="flex shrink-0 flex-wrap items-center gap-2.5 border-b border-border-subtle bg-bg-chrome px-3 py-2">
      {net.recording ? (
        <Button tone="danger" onClick={onStop}>
          <span className="flex items-center gap-1.5">
            <Square size={11} />
            Stop
          </span>
        </Button>
      ) : (
        <Button tone="danger" onClick={net.startRecording}>
          <span className="flex items-center gap-1.5">
            <Circle size={11} className="fill-white" />
            Record
          </span>
        </Button>
      )}

      <Button
        tone="primary"
        onClick={onExport}
        disabled={net.recorded.length === 0}
        title="Export the recording as JSON + CSV"
      >
        <span className="flex items-center gap-1.5">
          <Upload size={12} />
          Export
        </span>
      </Button>

      <span className="flex-1" />

      {latest === null ? null : (
        <span className="flex items-center gap-1.5">
          <Chip label="↓" value={formatRate(latest.downloadBytesPerSec)} />
          <Chip label="↑" value={formatRate(latest.uploadBytesPerSec)} />
        </span>
      )}
      <span
        className={
          net.streaming ? "tabular-nums text-text-primary" : "tabular-nums text-text-tertiary"
        }
      >
        {statusText(net.streaming, net.recording, latest?.elapsed ?? 0)}
      </span>
    </div>
  )
}

function Chip({ label, value }: { label: string; value: string }) {
  return (
    <span className="flex items-center gap-1 rounded-full bg-white/[0.07] px-2 py-0.5">
      <span className="text-[10px] font-semibold text-accent">{label}</span>
      <span className="tabular-nums text-[11.5px] text-text-primary">{value}</span>
    </span>
  )
}

