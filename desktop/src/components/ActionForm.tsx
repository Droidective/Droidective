import { useMemo, useState } from "react"
import {
  FeatureHeader,
  FieldRow,
  Outcome,
  RunControls,
  runLabel,
} from "@/components/ActionFormParts"
import { Switch } from "@/components/Controls"
import { useArmedConfirm } from "@/hooks/useArmedConfirm"
import { useTargets } from "@/hooks/useTargets"
import { asDaemonError, runAction } from "@/lib/daemon"
import { initialValues, missingRequired, runFields, type FormValues } from "@/lib/fields"
import { runOnTargets } from "@/lib/runner"
import type { DaemonError, Device, FeatureSummary, RunResponse } from "@/lib/wire"

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
  const confirm = useArmedConfirm()
  const { serials, runningOnAll } = useTargets()

  const missing = useMemo(() => missingRequired(feature, values), [feature, values])
  // Something to run on, which is the device bar's answer rather than this
  // screen's: with Run on all in effect it is every ready device.
  const ready = serials.length > 0
  // The registry says this one acts on an app, and nothing has been chosen.
  const needsApp = feature.needsBundle && packageId === null
  // Scoped to this feature on this device, so switching either expires the
  // arming instead of carrying it across.
  const target = device?.serial ?? ""
  const confirming = feature.isDestructive && confirm.isArmed(feature.id, target)

  const run = async () => {
    if (feature.isDestructive && !confirming) {
      confirm.arm(feature.id, target)
      return
    }
    if (!device) return
    confirm.disarm()
    setRunning(true)
    setResult(null)
    setError(null)
    try {
      setResult(
        await runOnTargets(runAction, {
          featureId: feature.id,
          serials,
          platform: device.platform,
          fields: runFields(feature, values, toggleOn, packageId),
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
        label={runLabel(running, confirming, runningOnAll ? serials.length : 1)}
        tone={feature.isDestructive ? "danger" : "primary"}
        disabled={running || !ready || needsApp || missing.length > 0}
        device={device}
        ready={ready}
        missing={missing}
        needsApp={needsApp}
        confirming={confirming}
        onRun={() => void run()}
        onCancel={confirm.disarm}
      />

      <Outcome error={error} result={result} />
    </div>
  )
}
