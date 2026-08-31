import { useCallback, useEffect, useMemo, useState } from "react"
import { useQuickRun } from "@/hooks/useQuickRun"
import { useQuickSession, type QuickSession } from "@/hooks/useQuickSession"
import { asDaemonError } from "@/lib/daemon"
import { type FormValues } from "@/lib/fields"
import { moveInGrid, openableScreens, quickActions, quickCommands } from "@/lib/quick-actions"
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
  /** The action waiting on an app, after its device was settled. */
  pickingApp: FeatureSummary | null
  /** Which device that app list belongs to. */
  bundleSerial: string | null
  running: boolean
  /** A destructive action waiting for its confirming second press. */
  armed: string | null
  outcome: { message: string; ok: boolean } | null
  activate: (feature: FeatureSummary) => void
  submitForm: (values: FormValues, toggleOn: boolean) => void
  pickDevice: (serials: string[]) => void
  pickApp: (packageId: string) => void
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
