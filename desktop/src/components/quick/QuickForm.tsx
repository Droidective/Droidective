import { useState } from "react"
import { FieldRow } from "@/components/ActionFormParts"
import { Button, Switch } from "@/components/Controls"
import { initialValues, missingRequired, type FormValues } from "@/lib/fields"
import type { FeatureSummary } from "@/lib/wire"

/**
 * A form action's fields, in the panel — the Mac's `QuickActionFormView`.
 *
 * The rows are the same `FieldRow` the in-app form uses, so a field looks and
 * validates the same whichever way it was reached.
 *
 * **A toggle lands here too**, and that is a decision rather than an
 * accident: the Mac flips one from the override state it tracks, which this
 * app does not keep, so running one would mean guessing a direction and
 * writing it to a device. Asking is the honest version, and it is the same
 * answer the per-feature hotkeys reached — those open the screen instead of
 * guessing.
 */
export function QuickForm({
  feature,
  running,
  onRun,
}: {
  feature: FeatureSummary
  running: boolean
  onRun: (values: FormValues, toggleOn: boolean) => void
}) {
  const [values, setValues] = useState<FormValues>(() => initialValues(feature))
  const [on, setOn] = useState(true)
  const missing = missingRequired(feature, values)
  const isToggle = feature.kind === "toggleAction"

  return (
    <form
      className="flex flex-col gap-3"
      onSubmit={(event) => {
        event.preventDefault()
        if (missing.length === 0 && !running) onRun(values, on)
      }}
    >
      {feature.subtitle === null ? null : (
        <p className="text-text-secondary">{feature.subtitle}</p>
      )}

      {isToggle ? (
        <div className="flex items-center justify-between">
          <span className="text-text-secondary">{feature.title}</span>
          <Switch checked={on} onChange={setOn} ariaLabel={feature.title} />
        </div>
      ) : (
        feature.fields.map((field) => (
          <FieldRow
            key={field.name}
            field={field}
            value={values[field.name] ?? ""}
            onChange={(value) => {
              setValues((current) => ({ ...current, [field.name]: value }))
            }}
          />
        ))
      )}

      <div className="flex items-center gap-2">
        <Button
          tone="primary"
          disabled={running || missing.length > 0}
          onClick={() => {
            if (missing.length === 0 && !running) onRun(values, on)
          }}
        >
          {running ? "Running…" : "Run"}
        </Button>
        {missing.length === 0 ? null : (
          <span className="text-[11.5px] text-text-tertiary">
            Fill in {missing.join(", ")}.
          </span>
        )}
      </div>
    </form>
  )
}
