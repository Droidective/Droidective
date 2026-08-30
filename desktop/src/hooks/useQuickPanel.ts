import { useCallback, useEffect, useMemo, useState } from "react"
import { useQuickSession, type QuickSession } from "@/hooks/useQuickSession"
import { asDaemonError, hideQuickPanel, runAction } from "@/lib/daemon"
import { runFields, type FormValues } from "@/lib/fields"
import { moveInGrid, openableScreens, quickActions, quickCommands } from "@/lib/quick-actions"
import { runOnTargets } from "@/lib/runner"
import type { CustomCommand, Device, FeatureSummary } from "@/lib/wire"

/** The columns the grid wraps at — the Mac's five. */
export const COLUMNS = 5

export interface QuickPanelState {
  session: QuickSession
  query: string
  setQuery: (query: string) => void
  highlight: number
  setHighlight: (index: number) => void
  actions: FeatureSummary[]
  commands: CustomCommand[]
  screens: FeatureSummary[]
  ready: Device[]
  /** The screen in front: null for the grid, else a form or the device picker. */
  form: FeatureSummary | null
  picking: FeatureSummary | null
  running: boolean
  /** A destructive action waiting for its confirming second press. */
  armed: string | null
  outcome: { message: string; ok: boolean } | null
  activate: (feature: FeatureSummary) => void
  submitForm: (values: FormValues, toggleOn: boolean) => void
  pickDevice: (serials: string[]) => void
  move: (direction: "up" | "down" | "left" | "right") => void
  enter: () => void
  back: () => void
  runCommand: (id: string) => void
}

/**
 * The panel's state: what it lists, and where the highlight is.
 *
 * Running is next door in `useQuickRun`, because the two are genuinely
 * separate — this one narrows lists as a query is typed, and that one owns a
 * stack one screen deep and an action in flight.
 */
export function useQuickPanel(): QuickPanelState {
  const session = useQuickSession()
  const [query, setQuery] = useState("")
  const [highlight, setHighlight] = useState(0)

  const { features, layout, devices } = session
  const actions = useMemo(
    () =>
      quickActions(features, {
        query,
        disabled: layout.disabledFeatures,
        favorites: layout.favorites,
        hidden: layout.quickPanelHiddenIds,
      }),
    [features, layout, query],
  )
  const commands = useMemo(() => quickCommands(session.commands, query), [session.commands, query])
  const screens = useMemo(
    () => openableScreens(features, { query, disabled: layout.disabledFeatures }),
    [features, layout.disabledFeatures, query],
  )
  const ready = useMemo(() => devices.filter((device) => device.state === "device"), [devices])

  const run = useQuickRun({ ready, closeAfterRun: layout.quickPanelCloseAfterRun })

  // A changed list must not leave the highlight — or an arming — pointing at
  // whatever slid into that position.
  const { disarm } = run
  useEffect(() => {
    setHighlight(0)
    disarm()
  }, [query, disarm])

  return {
    session,
    query,
    setQuery,
    highlight,
    setHighlight,
    actions,
    commands,
    screens,
    ready,
    ...run,
    move: useCallback(
      (direction: "up" | "down" | "left" | "right") => {
        setHighlight((current) => moveInGrid(actions.length, current, direction, COLUMNS))
      },
      [actions.length],
    ),
    enter: useCallback(() => {
      const feature = actions[highlight]
      if (feature !== undefined) run.activate(feature)
    }, [actions, highlight, run]),
    runCommand: useCallback(
      (id: string) => {
        void session.runCommand(id).then(run.report, (thrown: unknown) => {
          run.report({ message: asDaemonError(thrown).message, ok: false })
        })
      },
      [session, run],
    ),
  }
}

/** One action against the chosen targets, as a message for the footer. */
async function runOne(
  feature: FeatureSummary,
  serials: string[],
  values: FormValues,
  on: boolean,
  ready: readonly Device[],
): Promise<{ message: string; ok: boolean }> {
  try {
    const result = await runOnTargets(runAction, {
      featureId: feature.id,
      // A device-free action still needs one target, so it runs once.
      serials: serials.length > 0 ? serials : [""],
      platform: ready.find((device) => device.serial === serials[0])?.platform ?? "android",
      fields: runFields(feature, values, on, null),
    })
    if (result === null) return { message: "Nothing to run on.", ok: false }
    return { message: result.message, ok: result.ok }
  } catch (thrown) {
    return { message: asDaemonError(thrown).message, ok: false }
  }
}

/**
 * Running something, and the two questions that can come first.
 *
 * A destructive action arms and waits for a second press, as it does
 * everywhere else in both apps. A device-scoped one with several devices
 * connected pushes the interstitial rather than guessing — the panel has no
 * device bar to have chosen with, which is the Mac's reason too. A form action
 * and a toggle both push their own screen, the toggle because this app does
 * not track the override state the Mac flips one from.
 */
function useQuickRun({
  ready,
  closeAfterRun,
}: {
  ready: readonly Device[]
  closeAfterRun: boolean
}) {
  const [form, setForm] = useState<FeatureSummary | null>(null)
  const [picking, setPicking] = useState<FeatureSummary | null>(null)
  const [held, setHeld] = useState<{ values: FormValues; on: boolean } | null>(null)
  const [outcome, setOutcome] = useState<{ message: string; ok: boolean } | null>(null)
  const [running, setRunning] = useState(false)
  const [armed, setArmed] = useState<string | null>(null)

  const perform = useCallback(
    async (feature: FeatureSummary, serials: string[], values: FormValues, on: boolean) => {
      setRunning(true)
      try {
        const answer = await runOne(feature, serials, values, on, ready)
        setOutcome(answer)
        if (answer.ok && closeAfterRun) void hideQuickPanel()
      } finally {
        setRunning(false)
        setForm(null)
        setPicking(null)
        setHeld(null)
      }
    },
    [ready, closeAfterRun],
  )

  const start = useCallback(
    (feature: FeatureSummary, values: FormValues, on: boolean) => {
      if (!feature.needsDevice) {
        void perform(feature, [], values, on)
        return
      }
      if (ready.length === 0) {
        setOutcome({ message: "No device connected.", ok: false })
        return
      }
      if (ready.length > 1) {
        setHeld({ values, on })
        setPicking(feature)
        return
      }
      void perform(feature, [ready[0]?.serial ?? ""], values, on)
    },
    [ready, perform],
  )

  return {
    form,
    picking,
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
      [armed, start],
    ),
    submitForm: useCallback(
      (values: FormValues, on: boolean) => {
        if (form !== null) start(form, values, on)
      },
      [form, start],
    ),
    pickDevice: useCallback(
      (serials: string[]) => {
        if (picking !== null) void perform(picking, serials, held?.values ?? {}, held?.on ?? true)
      },
      [picking, held, perform],
    ),
    back: useCallback(() => {
      if (form === null && picking === null) {
        void hideQuickPanel()
        return
      }
      setForm(null)
      setPicking(null)
      setHeld(null)
    }, [form, picking]),
  }
}
