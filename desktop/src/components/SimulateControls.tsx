/**
 * The Simulate hub's own three controls.
 *
 * Here rather than in `Controls.tsx` because none of them is general: the
 * slider carries its value in its label, the field is this screen's two-column
 * row, and Apply knows about `HubActions`.
 */

import { Button } from "@/components/Controls"
import type { HubActions } from "@/hooks/useHubAction"


/** SwiftUI's `Slider` with the value read out above it, as every section does. */
export function Slider({
  label,
  ariaLabel,
  min,
  max,
  step,
  value,
  onChange,
}: {
  label: string
  ariaLabel: string
  min: number
  max: number
  step: number
  value: number
  onChange: (value: number) => void
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-text-primary">{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        aria-label={ariaLabel}
        onChange={(event) => {
          onChange(Number(event.target.value))
        }}
        className="accent-accent"
      />
    </div>
  )
}

export function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-[11.5px] text-text-tertiary">{label}</span>
      {children}
    </div>
  )
}

/** The section's own Apply, disabled only while its own action is in flight. */
export function Apply({
  actions,
  featureId,
  fields,
}: {
  actions: HubActions
  featureId: string
  fields: Parameters<HubActions["run"]>[1]
}) {
  return (
    <div>
      <Button
        tone="primary"
        disabled={actions.runningId === featureId}
        onClick={() => {
          actions.run(featureId, fields)
        }}
      >
        Apply
      </Button>
    </div>
  )
}
