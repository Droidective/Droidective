import { Banner, Button, Select, Slider, Switch, TextInput } from "@/components/Controls"
import { ResultActions } from "@/components/ResultActions"
import { coerce } from "@/lib/fields"
import { iconForFeature } from "@/lib/icons"
import type { DaemonError, Device, FeatureField, FeatureSummary, RunResponse } from "@/lib/wire"

/**
 * The pieces an action form is made of: its header, one rendered registry
 * field, the run controls, and what came back.
 *
 * Together in one file so `ActionForm` stays about *running* a feature. The
 * part that grows is the field mapping — a `FieldControl` case to a control —
 * and the part worth reading twice is the outcome: a non-zero adb exit is an
 * `ok:false` on a 200, not a thrown error, so a failed run is reported in the
 * result banner rather than the error one. That is a distinction `AdbClient`
 * exists to preserve.
 */

/**
 * What the button says.
 *
 * A fan-out names its count on the button rather than only in the bar's switch:
 * "Run on 3 devices" is the one place someone sees how many before pressing it.
 */
export function runLabel(running: boolean, confirming: boolean, targets: number): string {
  if (running) return "Running…"
  if (confirming) return "Really run it?"
  return targets > 1 ? `Run on ${String(targets)} devices` : "Run"
}

export function FeatureHeader({ feature }: { feature: FeatureSummary }) {
  const Icon = iconForFeature(feature.id, feature.category)
  return (
    <header className="flex items-start gap-3">
      <Icon size={22} className="mt-0.5 shrink-0 text-accent" />
      <div className="min-w-0">
        <h2 className="text-[17px] font-semibold text-text-primary" data-selectable>
          {feature.title}
        </h2>
        {feature.subtitle ? (
          <p className="mt-0.5 text-text-secondary" data-selectable>
            {feature.subtitle}
          </p>
        ) : null}
      </div>
    </header>
  )
}

export function RunControls({
  label,
  tone,
  disabled,
  device,
  ready,
  missing,
  needsApp,
  confirming,
  onRun,
  onCancel,
}: {
  label: string
  tone: "primary" | "danger"
  disabled: boolean
  device: Device | null
  ready: boolean
  missing: string[]
  needsApp: boolean
  confirming: boolean
  onRun: () => void
  onCancel: () => void
}) {
  return (
    <div className="flex items-center gap-3">
      <Button
        onClick={onRun}
        tone={tone}
        disabled={disabled}
        title={ready ? undefined : "Select a ready device first"}
      >
        {label}
      </Button>
      {confirming ? <Button onClick={onCancel}>Cancel</Button> : null}
      {needsApp ? (
        <span className="text-text-tertiary">Pick an app in the Apps tab first</span>
      ) : null}
      {missing.length > 0 ? (
        <span className="text-text-tertiary">Fill in {missing.join(", ")}</span>
      ) : null}
      {!ready && device ? (
        <span className="text-text-tertiary">
          {device.label} is {device.state}
        </span>
      ) : null}
    </div>
  )
}

export function FieldRow({
  field,
  value,
  onChange,
}: {
  field: FeatureField
  value: string | number | boolean
  onChange: (value: string | number | boolean) => void
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-text-secondary">
        {field.label}
        {field.optional ? <span className="text-text-tertiary"> (optional)</span> : null}
      </span>
      <Control field={field} value={value} onChange={onChange} />
      {field.description ? (
        <span className="text-text-tertiary">{field.description}</span>
      ) : null}
    </label>
  )
}

function Control({
  field,
  value,
  onChange,
}: {
  field: FeatureField
  value: string | number | boolean
  onChange: (value: string | number | boolean) => void
}) {
  switch (field.control) {
    case "switch":
      return <Switch checked={value === true} onChange={onChange} ariaLabel={field.label} />
    case "slider":
      return (
        <Slider
          value={typeof value === "number" ? value : (field.min ?? 0)}
          min={field.min ?? 0}
          max={field.max ?? 100}
          step={field.step ?? 1}
          onChange={onChange}
        />
      )
    case "select":
      return (
        <Select
          value={String(value)}
          options={field.options}
          onChange={(next) => {
            onChange(next)
          }}
        />
      )
    case "number":
      return (
        <TextInput
          type="number"
          value={String(value)}
          placeholder={field.placeholder ?? undefined}
          onChange={(next) => {
            onChange(coerce(field, next))
          }}
        />
      )
    default:
      // text, bundle and preset all render as free text. A preset's stored
      // suggestions and a bundle picker need surfaces this app has yet to
      // grow; typing the value works today.
      return (
        <TextInput
          value={String(value)}
          placeholder={field.placeholder ?? undefined}
          onChange={(next) => {
            onChange(coerce(field, next))
          }}
        />
      )
  }
}

export function Outcome({ error, result }: { error: DaemonError | null; result: RunResponse | null }) {
  return (
    <>
      {error ? (
        <Banner tone="error">
          {error.message}
          {error.detail ? <div className="mt-1 opacity-70">{error.detail}</div> : null}
        </Banner>
      ) : null}
      {result ? (
        // A non-zero adb exit comes back as ok:false with a 200, not as an
        // error — so a failed run is reported here, not in the banner above.
        <Banner tone={result.ok ? "ok" : "error"}>
          {result.message}
          {result.copyText ? (
            <pre className="mt-2 overflow-x-auto text-[12px] opacity-80">{result.copyText}</pre>
          ) : null}
          {result.revealPath ? (
            <div className="mt-1 opacity-70">Saved to {result.revealPath}</div>
          ) : null}
          {result.needsAdbKeyboard ? (
            <div className="mt-1 opacity-70">
              Needs the ADBKeyboard IME installed on the device.
            </div>
          ) : null}
          <ResultActions result={result} />
        </Banner>
      ) : null}
    </>
  )
}

