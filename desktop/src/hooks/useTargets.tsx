import { createContext, useContext, useMemo } from "react"
import { effectiveRunOnAll, targetSerials } from "@/lib/targets"
import type { Device, FeatureSummary } from "@/lib/wire"

export interface Targets {
  /** Every device this run should reach, the selected one first. */
  serials: string[]
  /** Whether a fan-out is actually in effect, so a screen can say so. */
  runningOnAll: boolean
}

const TargetsContext = createContext<Targets>({ serials: [], runningOnAll: false })

/**
 * Who an action runs on, for the whole window.
 *
 * A context for the reason the notifications are one: the answer depends on the
 * device bar's switch *and* the focused feature, both of which live above the
 * pane tree, and every screen that runs something needs it. Threading a serial
 * list down through the pane area to each pane would be prop-drilling a value
 * the Mac keeps on `AppState`.
 */
export function TargetsProvider({
  devices,
  selected,
  focusedFeature,
  runOnAll,
  children,
}: {
  devices: Device[]
  selected: Device | null
  /** The feature in the focused tab — what decides whether a fan-out applies. */
  focusedFeature: FeatureSummary | null
  runOnAll: boolean
  children: React.ReactNode
}) {
  const runningOnAll = effectiveRunOnAll(runOnAll, focusedFeature)
  const serials = targetSerials(devices, selected, runningOnAll)
  // Keyed on the joined serials, so a poll that returns the same devices does
  // not hand every consumer a new array and re-run their effects.
  const fingerprint = serials.join(",")
  const value = useMemo<Targets>(
    () => ({ serials: fingerprint === "" ? [] : fingerprint.split(","), runningOnAll }),
    [fingerprint, runningOnAll],
  )
  return <TargetsContext value={value}>{children}</TargetsContext>
}

export function useTargets(): Targets {
  return useContext(TargetsContext)
}
