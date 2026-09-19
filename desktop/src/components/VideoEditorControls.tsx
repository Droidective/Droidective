import { Crop, FlipHorizontal, FlipVertical, RotateCcw, RotateCw, Volume2, VolumeX, X } from "lucide-react"
import type { ReactNode } from "react"
import { Button } from "@/components/Controls"
import { IconButton } from "@/components/Hub"
import {
  COMPRESSIONS,
  FORMATS,
  isFullFrame,
  SPEEDS,
  timecode,
  turned,
  withTrim,
  type CompressionLevel,
  type EditState,
  type VideoFormat,
} from "@/lib/video-edit"

export interface ControlsProps {
  edit: EditState
  apply: (change: (edit: EditState) => EditState) => void
  duration: number
  /** Where the playhead is, for "Trim from here". */
  position: number
  cropping: boolean
  onCropping: (on: boolean) => void
}

/**
 * The editor's three control rows — Trim, Transform, and Output.
 *
 * Section for section with the Mac's `VideoEditorPane`: the same controls, the
 * same labels, the same order, so someone moving between the two finds them
 * where they left them.
 */
export function VideoEditorControls(props: ControlsProps) {
  return (
    <div className="flex flex-col gap-3 border-t border-border-subtle px-3 py-3">
      <TrimRow {...props} />
      <TransformRow {...props} />
      <OutputRow {...props} />
    </div>
  )
}

function TrimRow({ edit, apply, duration, position }: ControlsProps) {
  const trimmed = edit.trimStart !== null || edit.trimEnd !== null
  return (
    <Row label="Trim">
      <Button
        onClick={() => {
          apply((current) => withTrim(current, position, current.trimEnd, duration))
        }}
      >
        Start here
      </Button>
      <Button
        onClick={() => {
          apply((current) => withTrim(current, current.trimStart, position, duration))
        }}
      >
        End here
      </Button>
      {trimmed ? (
        <>
          <span className="text-[12px] text-text-secondary">
            {timecode(edit.trimStart ?? 0)} – {timecode(edit.trimEnd ?? duration)}
          </span>
          <Button
            onClick={() => {
              apply((current) => withTrim(current, null, null, duration))
            }}
          >
            Clear
          </Button>
        </>
      ) : (
        <span className="text-[12px] text-text-tertiary">Whole clip</span>
      )}
    </Row>
  )
}

function TransformRow({ edit, apply, cropping, onCropping }: ControlsProps) {
  const cropped = edit.crop !== null && !isFullFrame(edit.crop)
  return (
    <Row label="Transform">
      <IconButton
        icon={<RotateCcw size={14} />}
        label="Rotate left"
        onClick={() => {
          apply((current) => turned(current, false))
        }}
      />
      <IconButton
        icon={<RotateCw size={14} />}
        label="Rotate right"
        onClick={() => {
          apply((current) => turned(current, true))
        }}
      />
      <Pill
        on={edit.flipH}
        icon={<FlipHorizontal size={13} />}
        label="Flip H"
        onClick={() => {
          apply((current) => ({ ...current, flipH: !current.flipH }))
        }}
      />
      <Pill
        on={edit.flipV}
        icon={<FlipVertical size={13} />}
        label="Flip V"
        onClick={() => {
          apply((current) => ({ ...current, flipV: !current.flipV }))
        }}
      />
      <Pill
        on={cropping}
        icon={<Crop size={13} />}
        label={cropped ? "Edit Crop" : "Crop"}
        onClick={() => {
          onCropping(!cropping)
        }}
      />
      {cropped ? (
        <IconButton
          icon={<X size={14} />}
          label="Remove crop"
          onClick={() => {
            apply((current) => ({ ...current, crop: null }))
          }}
        />
      ) : null}
    </Row>
  )
}

function OutputRow({ edit, apply }: ControlsProps) {
  return (
    <Row label="Output">
      <Picker
        label="Speed"
        value={String(edit.speed)}
        options={SPEEDS.map((speed) => ({ value: String(speed), label: `${speed}×` }))}
        onChange={(value) => {
          apply((current) => ({ ...current, speed: Number(value) }))
        }}
      />
      <Pill
        on={edit.mute}
        icon={edit.mute ? <VolumeX size={13} /> : <Volume2 size={13} />}
        label="Mute"
        onClick={() => {
          apply((current) => ({ ...current, mute: !current.mute }))
        }}
      />
      <Picker
        label="Format"
        value={edit.format}
        options={FORMATS.map((f) => ({ value: f.value, label: f.label }))}
        onChange={(value) => {
          apply((current) => ({ ...current, format: value as VideoFormat }))
        }}
      />
      <Picker
        label="Compression"
        value={edit.compression}
        options={COMPRESSIONS.map((c) => ({ value: c.value, label: c.label }))}
        onChange={(value) => {
          apply((current) => ({ ...current, compression: value as CompressionLevel }))
        }}
      />
    </Row>
  )
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="w-[74px] shrink-0 text-[11.5px] text-text-tertiary">{label}</span>
      {children}
    </div>
  )
}

function Pill({
  on,
  icon,
  label,
  onClick,
}: {
  on: boolean
  icon: ReactNode
  label: string
  onClick: () => void
}) {
  return (
    <button
      type="button"
      aria-pressed={on}
      onClick={onClick}
      className={
        on
          ? "flex items-center gap-1.5 rounded-md bg-accent/[0.18] px-2.5 py-1.5 text-[12.5px] text-accent"
          : "flex items-center gap-1.5 rounded-md bg-bg-raised px-2.5 py-1.5 text-[12.5px] text-text-primary transition hover:bg-border-subtle"
      }
    >
      {icon}
      {label}
    </button>
  )
}

function Picker({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: string
  options: { value: string; label: string }[]
  onChange: (value: string) => void
}) {
  return (
    <label className="flex items-center gap-1.5 text-[11.5px] text-text-tertiary">
      {label}
      <select
        aria-label={label}
        value={value}
        onChange={(event) => {
          onChange(event.target.value)
        }}
        className="rounded-md border border-border-subtle bg-bg-root px-2 py-1 text-[12px] text-text-primary outline-none focus:border-accent"
      >
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  )
}
