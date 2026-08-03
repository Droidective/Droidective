import { useMemo, useState } from "react"
import { Banner, Button, Select, Slider, Switch, TextInput } from "@/components/Controls"
import { asDaemonError, runAction } from "@/lib/daemon"
import { iconForFeature } from "@/lib/icons"
import { coerce, initialValues, missingRequired, runFields, type FormValues } from "@/lib/fields"
import type { DaemonError, Device, FeatureField, FeatureSummary, RunResponse } from "@/lib/wire"

/** The detail pane: a feature's parameters, a Run button, and what came back. */
export function ActionForm({
  feature,
  device,
  packageId,
}: {
  feature: FeatureSummary
  device: Device | null
  /** The app chosen in the Apps tab, if any. */
  packageId: string | null
}) {
  // Re-keyed by feature id from the parent, so state resets when the
  // selection changes rather than leaking one feature's input into the next.
  const [values, setValues] = useState<FormValues>(() => initialValues(feature))
  const [toggleOn, setToggleOn] = useState(true)
  const [running, setRunning] = useState(false)
  const [result, setResult] = useState<RunResponse | null>(null)
  const [error, setError] = useState<DaemonError | null>(null)
  const [confirming, setConfirming] = useState(false)

  const missing = useMemo(() => missingRequired(feature, values), [feature, values])
  const ready = device?.state === "device"
  // The registry says this one acts on an app, and nothing has been chosen.
  const needsApp = feature.needsBundle && packageId === null

  const run = async () => {
    if (feature.isDestructive && !confirming) {
      setConfirming(true)
      return
    }
    if (!device) return
    setConfirming(false)
    setRunning(true)
    setResult(null)
    setError(null)
    try {
      const fields = runFields(feature, values, toggleOn, packageId)
      setResult(
        await runAction({
          featureId: feature.id,
          serial: device.serial,
          platform: device.platform,
          ...(fields ? { fields } : {}),
        }),
      )
    } catch (thrown) {
      setError(asDaemonError(thrown))
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto p-6">
      <FeatureHeader feature={feature} />

      {feature.kind === "toggleAction" || feature.fields.length > 0 ? (
        <div className="flex flex-col gap-4 rounded-lg border border-border-subtle bg-bg-surface p-4">
          {feature.kind === "toggleAction" ? (
            <Switch checked={toggleOn} onChange={setToggleOn} label={toggleOn ? "On" : "Off"} />
          ) : null}
          {feature.fields.map((field) => (
            <FieldRow
              key={field.name}
              field={field}
              value={values[field.name] ?? ""}
              onChange={(next) => {
                setValues((current) => ({ ...current, [field.name]: next }))
              }}
            />
          ))}
        </div>
      ) : null}

      <RunControls
        label={running ? "Running…" : confirming ? "Really run it?" : "Run"}
        tone={feature.isDestructive ? "danger" : "primary"}
        disabled={running || !ready || needsApp || missing.length > 0}
        device={device}
        ready={ready}
        missing={missing}
        needsApp={needsApp}
        confirming={confirming}
        onRun={() => void run()}
        onCancel={() => {
          setConfirming(false)
        }}
      />

      <Outcome error={error} result={result} />
    </div>
  )
}

function FeatureHeader({ feature }: { feature: FeatureSummary }) {
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

function RunControls({
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

function Outcome({ error, result }: { error: DaemonError | null; result: RunResponse | null }) {
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
        </Banner>
      ) : null}
    </>
  )
}

function FieldRow({
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
