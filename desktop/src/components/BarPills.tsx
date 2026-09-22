/**
 * The device bar's two pills, bound to its props.
 *
 * Here rather than inline because `DeviceBar` is at oxlint's dependency
 * ceiling, and because both are the same kind of thing: state that belongs to
 * the *window* rather than to any screen, and so has to outlive whichever tab
 * set it.
 */

import { AppPill } from "@/components/AppPill"
import type { DeviceBarProps } from "@/components/DeviceBar"
import { NotificationBell } from "@/components/NotificationPanel"
import { OverridesPill } from "@/components/OverridesPill"

export const BarPills = {
  Bell: NotificationBell,
  App: ({ bar }: { bar: DeviceBarProps }) => (
    <AppPill
      serial={bar.selected?.serial ?? null}
      packageId={bar.packageId}
      onSelect={bar.onSelectPackage}
    />
  ),
  Overrides: ({ bar }: { bar: DeviceBarProps }) => (
    <OverridesPill
      overrides={bar.overrides}
      busy={bar.overridesBusy}
      onReset={bar.onResetOverride}
      onResetAll={bar.onResetAllOverrides}
    />
  ),
}
