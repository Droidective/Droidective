import { useState } from "react"
import { CircleDot, Pause, Play, Square, Video } from "lucide-react"

import { Banner, Button } from "@/components/Controls"
import { NoDevice } from "@/components/NoDevice"
import { RecordOptionsCard } from "@/components/RecordOptions"
import { useScreenRecord } from "@/hooks/useScreenRecord"
import { DEFAULT_RECORD_OPTIONS, durationLabel, fileSizeLabel, type RecordOptions } from "@/lib/record"
import { cn } from "@/lib/cn"
import type { Device } from "@/lib/wire"

/**
 * Screen Record — the Mac's `ScreenRecordView`.
 *
 * Recording is the scrcpy stream the mirror already receives, piped into
 * ffmpeg on the daemon rather than into a decoder, so it needs no separate
 * scrcpy install either. Two things the Mac's screen has and this does not,
 * both said on the screen rather than quietly missing: **audio**, because
 * scrcpy carries it as a second stream that has to be interleaved against the
 * video's clock, and the **live preview**, which would mean decoding the
 * stream twice on the way to a file.
 */
export function ScreenRecordPane({ device }: { device: Device | null }) {
  const record = useScreenRecord()
  const [options, setOptions] = useState<RecordOptions>(DEFAULT_RECORD_OPTIONS)
  const [showAdvanced, setShowAdvanced] = useState(false)

  if (device === null) return <NoDevice feature="screen-record" title="Screen Record" />

  const recording = record.status?.recording === true
  const paused = record.status?.paused === true

  if (record.finished !== null) {
    return (
      <Finished
        durationSeconds={record.finished.durationSeconds}
        sizeBytes={record.finished.sizeBytes}
        onSave={record.save}
        onDiscard={record.discard}
      />
    )
  }

  return (
    <div className="flex h-full flex-col items-center justify-center gap-7 overflow-auto p-7">
      <div className="flex w-full max-w-[420px] flex-col items-center gap-4">
        <div
          className={cn(
            "flex h-24 w-24 items-center justify-center rounded-full",
            recording ? "bg-danger/15" : "bg-accent/12",
          )}
        >
          {recording ? (
            <CircleDot size={38} className={paused ? "text-text-secondary" : "text-danger"} />
          ) : (
            <Video size={38} className="text-accent" />
          )}
        </div>

        {recording ? (
          <div className="flex flex-col items-center gap-1">
            <span className="font-mono text-[30px] font-semibold tabular-nums text-text-primary">
              {durationLabel(record.elapsed)}
            </span>
            <span className={cn("text-[13px]", paused ? "text-text-secondary" : "text-danger")}>
              {paused ? "Paused" : "Recording…"}
            </span>
          </div>
        ) : (
          <h2 className="text-[20px] font-semibold text-text-primary">Ready to record</h2>
        )}

        <Controls
          recording={recording}
          paused={paused}
          busy={record.busy}
          onStart={() => {
            record.start(device.serial, options)
          }}
          onPause={record.pause}
          onResume={() => {
            record.resume(options)
          }}
          onStop={record.stop}
        />

        {record.status?.ffmpegReady === false ? (
          <Banner tone="warn">
            ffmpeg isn&apos;t installed, so nothing can be recorded yet. Settings ▸ Tools can
            download it.
          </Banner>
        ) : null}
      </div>

      {recording ? null : (
        <div className="w-full max-w-[420px]">
          <RecordOptionsCard
            options={options}
            onChange={setOptions}
            showAdvanced={showAdvanced}
            onToggleAdvanced={() => {
              setShowAdvanced((was) => !was)
            }}
          />
          <p className="mt-3 text-center text-[12px] text-text-tertiary">
            Video only for now — the device&apos;s audio isn&apos;t recorded on Windows and Linux.
          </p>
        </div>
      )}
    </div>
  )
}

function Controls({
  recording,
  paused,
  busy,
  onStart,
  onPause,
  onResume,
  onStop,
}: {
  recording: boolean
  paused: boolean
  busy: boolean
  onStart: () => void
  onPause: () => void
  onResume: () => void
  onStop: () => void
}) {
  if (!recording) {
    return (
      <Button tone="primary" onClick={onStart} disabled={busy}>
        <span className="flex w-[220px] items-center justify-center gap-2">
          <CircleDot size={14} />
          {busy ? "Starting…" : "Record"}
        </span>
      </Button>
    )
  }
  return (
    <div className="flex gap-3">
      <Button onClick={paused ? onResume : onPause} disabled={busy}>
        <span className="flex w-[104px] items-center justify-center gap-2">
          {paused ? <Play size={13} /> : <Pause size={13} />}
          {paused ? "Resume" : "Pause"}
        </span>
      </Button>
      <Button tone="danger" onClick={onStop} disabled={busy}>
        <span className="flex w-[104px] items-center justify-center gap-2">
          <Square size={13} />
          Stop
        </span>
      </Button>
    </div>
  )
}

/**
 * The choice after a recording stops — the Mac's `RecordingDecision`.
 *
 * Discard and Save, without its Edit: the video editor is not ported yet, and
 * an Edit button that opened nothing would be worse than one that is absent.
 * Nothing is written to the captures folder until Save, which is what makes
 * Discard a real choice rather than a delete.
 */
function Finished({
  durationSeconds,
  sizeBytes,
  onSave,
  onDiscard,
}: {
  durationSeconds: number
  sizeBytes: number
  onSave: () => void
  onDiscard: () => void
}) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4 p-7 text-center">
      <div className="flex h-24 w-24 items-center justify-center rounded-full bg-accent/12">
        <Video size={38} className="text-accent" />
      </div>
      <h2 className="text-[15px] font-medium text-text-primary">Recording finished</h2>
      <p className="text-[13px] text-text-secondary">
        {durationLabel(durationSeconds)} · {fileSizeLabel(sizeBytes)}
      </p>
      <div className="flex gap-3">
        <Button tone="danger" onClick={onDiscard}>
          <span className="w-[104px]">Discard</span>
        </Button>
        <Button tone="primary" onClick={onSave}>
          <span className="w-[104px]">Save</span>
        </Button>
      </div>
      <p className="max-w-sm text-[12px] text-text-tertiary">
        Saving puts it in the captures folder. The video editor hasn&apos;t been ported yet, so
        there is no Edit here.
      </p>
    </div>
  )
}
