import { useCallback, useState } from "react"

import { asDaemonError, hideQuickPanel, runAction } from "@/lib/daemon"
import { runFields, type FormValues } from "@/lib/fields"
import { runOnTargets } from "@/lib/runner"
import type { Device, FeatureSummary } from "@/lib/wire"

/**
 * Running one thing from the panel, and the questions that can come first.
 *
 * Split from `useQuickPanel` because the two are genuinely separate: that one
 * narrows lists as a query is typed, and this one owns a stack up to two
 * screens deep and an action in flight.
 */

/** One action against the chosen targets, as a message for the footer. */
async function runOne(
  feature: FeatureSummary,
  serials: string[],
  values: FormValues,
  on: boolean,
  ready: readonly Device[],
  packageId: string | null,
): Promise<{ message: string; ok: boolean }> {
  try {
    const result = await runOnTargets(runAction, {
      featureId: feature.id,
      // A device-free action still needs one target, so it runs once.
      serials: serials.length > 0 ? serials : [""],
      platform: ready.find((device) => device.serial === serials[0])?.platform ?? "android",
      fields: runFields(feature, values, on, packageId),
    })
    if (result === null) return { message: "Nothing to run on.", ok: false }
    return { message: result.message, ok: result.ok }
  } catch (thrown) {
    return { message: asDaemonError(thrown).message, ok: false }
  }
}

/** What a held run still needs before it can go. */
interface Held {
  values: FormValues
  on: boolean
  /** Set once the device step is past, so the app list knows what to read. */
  serials?: string[]
}

/**
 * The panel's screen stack: a form, a device, an app — none, one, or two deep.
 *
 * Its own hook because it is four pieces of state that only ever change
 * together, and because "what is in front, and what is it holding?" is a
 * different question from "how does a run go?".
 */
function useRunStack() {
  const [form, setForm] = useState<FeatureSummary | null>(null)
  const [picking, setPicking] = useState<FeatureSummary | null>(null)
  const [pickingApp, setPickingApp] = useState<FeatureSummary | null>(null)
  const [held, setHeld] = useState<Held | null>(null)

  const clear = useCallback(() => {
    setForm(null)
    setPicking(null)
    setPickingApp(null)
    setHeld(null)
  }, [])

  return {
    form,
    picking,
    pickingApp,
    held,
    setForm,
    setPicking,
    setPickingApp,
    setHeld,
    clear,
    atRoot: form === null && picking === null && pickingApp === null,
  }
}

/**
 * Getting a run all the way to the daemon, asking whatever is still missing.
 *
 * A device-scoped action with several devices connected pushes the
 * interstitial rather than guessing — the panel has no device bar to have
 * chosen with, which is the Mac's reason too. A `needsBundle` action then asks
 * which app, once its device is settled.
 */
function useRunner(
  ready: readonly Device[],
  closeAfterRun: boolean,
  stack: ReturnType<typeof useRunStack>,
) {
  const [outcome, setOutcome] = useState<{ message: string; ok: boolean } | null>(null)
  const [running, setRunning] = useState(false)
  const { clear, setForm, setPicking, setPickingApp, setHeld } = stack

  const perform = useCallback(
    async (
      feature: FeatureSummary,
      serials: string[],
      values: FormValues,
      on: boolean,
      packageId: string | null,
    ) => {
      setRunning(true)
      try {
        const answer = await runOne(feature, serials, values, on, ready, packageId)
        setOutcome(answer)
        if (answer.ok && closeAfterRun) void hideQuickPanel()
      } finally {
        setRunning(false)
        clear()
      }
    },
    [ready, closeAfterRun, clear],
  )

  /**
   * The device is settled; the app may not be.
   *
   * A `needsBundle` action run with no package reaches the daemon as an
   * incomplete command and comes back as an adb error, which tells nobody what
   * to do — so the panel asks here instead. The Mac answers the same question
   * from its app-wide bundle selection, which a panel in its own window does
   * not have.
   */
  const withDevice = useCallback(
    (feature: FeatureSummary, serials: string[], values: FormValues, on: boolean) => {
      if (!feature.needsBundle) {
        void perform(feature, serials, values, on, null)
        return
      }
      // The form is finished with — its values are held — and only one screen
      // can be in front. Without this the form stays up and the app step is
      // rendered behind it, which reads as a Run button that does nothing.
      setForm(null)
      setPicking(null)
      setHeld({ values, on, serials })
      setPickingApp(feature)
    },
    [perform, setForm, setHeld, setPicking, setPickingApp],
  )

  const start = useCallback(
    (feature: FeatureSummary, values: FormValues, on: boolean) => {
      if (!feature.needsDevice) {
        void perform(feature, [], values, on, null)
        return
      }
      if (ready.length === 0) {
        setOutcome({ message: "No device connected.", ok: false })
        return
      }
      if (ready.length > 1) {
        setForm(null)
        setHeld({ values, on })
        setPicking(feature)
        return
      }
      withDevice(feature, [ready[0]?.serial ?? ""], values, on)
    },
    [ready, perform, withDevice, setForm, setHeld, setPicking],
  )

  return { outcome, setOutcome, running, perform, withDevice, start }
}

/**
 * Running something, and the questions that can come first.
 *
 * A destructive action arms and waits for a second press, as it does
 * everywhere else in both apps. A form action and a toggle both push their own
 * screen, the toggle because this app does not track the override state the
 * Mac flips one from.
 */
export function useQuickRun({
  ready,
  closeAfterRun,
}: {
  ready: readonly Device[]
  closeAfterRun: boolean
}) {
  const stack = useRunStack()
  const { outcome, setOutcome, running, perform, withDevice, start } = useRunner(
    ready,
    closeAfterRun,
    stack,
  )
  const [armed, setArmed] = useState<string | null>(null)
  const { clear, setForm, setPicking } = stack

  return {
    form: stack.form,
    picking: stack.picking,
    pickingApp: stack.pickingApp,
    /** The device the app list should read — the one already chosen. */
    bundleSerial: stack.held?.serials?.[0] ?? null,
    running,
    armed,
    outcome,
    report: setOutcome,
    disarm: useCallback(() => {
      setArmed(null)
    }, []),
    activate: useCallback(
      (feature: FeatureSummary) => {
        if (feature.isDestructive && armed !== feature.id) {
          setArmed(feature.id)
          return
        }
        setArmed(null)
        if (feature.kind === "formAction" || feature.kind === "toggleAction") {
          setForm(feature)
          return
        }
        start(feature, {}, true)
      },
      [armed, start, setForm],
    ),
    submitForm: useCallback(
      (values: FormValues, on: boolean) => {
        if (stack.form !== null) start(stack.form, values, on)
      },
      [stack.form, start],
    ),
    pickDevice: useCallback(
      (serials: string[]) => {
        if (stack.picking === null) return
        setPicking(null)
        withDevice(stack.picking, serials, stack.held?.values ?? {}, stack.held?.on ?? true)
      },
      [stack.picking, stack.held, withDevice, setPicking],
    ),
    pickApp: useCallback(
      (packageId: string) => {
        if (stack.pickingApp === null) return
        void perform(
          stack.pickingApp,
          stack.held?.serials ?? [],
          stack.held?.values ?? {},
          stack.held?.on ?? true,
          packageId,
        )
      },
      [stack.pickingApp, stack.held, perform],
    ),
    back: useCallback(() => {
      if (stack.atRoot) {
        void hideQuickPanel()
        return
      }
      clear()
    }, [stack.atRoot, clear]),
  }
}
