import { useMemo, useState } from "react"
import {
  FeatureHeader,
  FieldsCard,
  Outcome,
  RunConfirmDialog,
  RunControls,
  runLabel,
} from "@/components/ActionFormParts"
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
  const [confirming, setConfirming] = useState(false)
  const { serials, runningOnAll } = useTargets()

  const missing = useMemo(() => missingRequired(feature, values), [feature, values])
  // Something to run on, which is the device bar's answer rather than this
  // screen's: with Run on all in effect it is every ready device.
  const ready = serials.length > 0
  // The registry says this one acts on an app, and nothing has been chosen.
  const needsApp = feature.needsBundle && packageId === null
  const run = async () => {
    if (!device) return
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

      <FieldsCard
        feature={feature}
        values={values}
        toggleOn={toggleOn}
        onToggle={setToggleOn}
        onChange={(name, next) => {
          setValues((current) => ({ ...current, [name]: next }))
        }}
      />

      <RunControls
        label={runLabel(running, runningOnAll ? serials.length : 1)}
        tone={feature.isDestructive ? "danger" : "primary"}
        disabled={running || !ready || needsApp || missing.length > 0}
        device={device}
        ready={ready}
        missing={missing}
        needsApp={needsApp}
        onRun={() => {
          // The Mac raises a `confirmationDialog` here, so this does too. It
          // used to arm the button for a second press — a different
          // interaction for the same irreversible thing, in an app whose other
          // destructive verbs had already been converted.
          if (feature.isDestructive) setConfirming(true)
          else void run()
        }}
      />

      <Outcome error={error} result={result} />

      {confirming ? (
        <RunConfirmDialog
          feature={feature}
          onConfirm={() => {
            setConfirming(false)
            void run()
          }}
          onCancel={() => {
            setConfirming(false)
          }}
        />
      ) : null}
    </div>
  )
}
