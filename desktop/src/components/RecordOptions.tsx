import { ChevronRight } from "lucide-react"

import {
  BIT_RATE_CHOICES,
  FPS_CHOICES,
  RESOLUTION_CHOICES,
  TIME_LIMIT_CHOICES,
  type RecordOptions,
} from "@/lib/record"
import { cn } from "@/lib/cn"

/**
 * The recording's settings — the Mac's `optionsCard`.
 *
 * Resolution outside, the other three behind Advanced, in that order and with
 * those words. The card disappears once recording starts rather than greying
 * out: the options are locked either way, and the Mac frees the column too.
 */
export function RecordOptionsCard({
  options,
  onChange,
  showAdvanced,
  onToggleAdvanced,
}: {
  options: RecordOptions
  onChange: (options: RecordOptions) => void
  showAdvanced: boolean
  onToggleAdvanced: () => void
}) {
  return (
    <div className="rounded-lg border border-border-subtle bg-bg-surface p-3">
      <Row label="Resolution">
        <Choice
          label="Resolution"
          value={options.maxSize}
          choices={RESOLUTION_CHOICES}
          onChange={(maxSize) => {
            onChange({ ...options, maxSize })
          }}
        />
      </Row>

      <button
        type="button"
        onClick={onToggleAdvanced}
        aria-expanded={showAdvanced}
        className="mt-1 flex w-full items-center gap-1.5 py-1.5 text-left text-[13px] text-text-primary"
      >
        <ChevronRight
          size={12}
          className={cn("text-text-tertiary transition", showAdvanced ? "rotate-90" : "")}
        />
        Advanced options
      </button>

      {showAdvanced ? (
        <div className="space-y-1 pt-1">
          <Row label="Bit rate">
            <Choice
              label="Bit rate"
              value={options.bitRateMbps}
              choices={BIT_RATE_CHOICES}
              onChange={(bitRateMbps) => {
                onChange({ ...options, bitRateMbps })
              }}
            />
          </Row>
          <Row label="Max FPS">
            <Choice
              label="Max FPS"
              value={options.maxFps}
              choices={FPS_CHOICES}
              onChange={(maxFps) => {
                onChange({ ...options, maxFps })
              }}
            />
          </Row>
          <Row label="Time limit">
            <Choice
              label="Time limit"
              value={options.timeLimitSeconds}
              choices={TIME_LIMIT_CHOICES}
              onChange={(timeLimitSeconds) => {
                onChange({ ...options, timeLimitSeconds })
              }}
            />
          </Row>
        </div>
      ) : null}
    </div>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 py-1.5">
      <span className="text-[13px] text-text-primary">{label}</span>
      {children}
    </div>
  )
}

function Choice({
  label,
  value,
  choices,
  onChange,
}: {
  label: string
  value: number
  choices: { value: number; label: string }[]
  onChange: (value: number) => void
}) {
  return (
    <select
      aria-label={label}
      value={String(value)}
      onChange={(event) => {
        onChange(Number(event.target.value))
      }}
      className="rounded-md border border-border-subtle bg-bg-root px-2 py-1.5 text-[13px] text-text-primary"
    >
      {choices.map((choice) => (
        <option key={choice.value} value={choice.value}>
          {choice.label}
        </option>
      ))}
    </select>
  )
}
