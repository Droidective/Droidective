import { useCallback } from "react"

import { RolePicker } from "@/components/RolePicker"
import { useRoleCatalogue } from "@/hooks/useRoleCatalogue"
import type { WorkspaceController } from "@/hooks/useWorkspace"
import { applyEverything, applyRole, dismissRolePicker, type Role } from "@/lib/roles"
import { currentWindowLabel } from "@/lib/window-layout"
import { MAIN_WINDOW } from "@/lib/workspaces"
import type { FeatureSummary } from "@/lib/wire"

/**
 * Shows the role picker when it is due, and applies what it answers.
 *
 * "Due" is first launch *and* the main window: the Mac shows it once, before
 * the tour, and a second window opening onto a full-screen picker would be
 * asking the same question again about a layout that is already curated.
 *
 * Re-opening it later is Settings ▸ General's job, which is why `open` is a
 * prop rather than local state — two places decide when it shows, and only one
 * of them is this component.
 */
export function RolePickerHost({
  workspace,
  features,
  open,
  onClose,
}: {
  workspace: WorkspaceController
  features: readonly FeatureSummary[]
  /** Forced open from Settings, whatever the layout says. */
  open: boolean
  onClose: () => void
}) {
  const catalogue = useRoleCatalogue()
  const { curate } = workspace
  // In the URL the window was opened with, so it cannot change under us.
  const isMainWindow = currentWindowLabel(globalThis.location.search) === MAIN_WINDOW
  const firstLaunch = !workspace.layout.roleChosen && isMainWindow

  const pick = useCallback(
    (role: Role, includeReactNative: boolean) => {
      if (catalogue === null) return
      curate((layout) => applyRole(layout, role, catalogue, features, includeReactNative))
      onClose()
    },
    [catalogue, curate, features, onClose],
  )

  if (catalogue === null || (!open && !firstLaunch)) return null

  return (
    <RolePicker
      catalogue={catalogue}
      features={features}
      onPick={pick}
      onEverything={() => {
        curate((layout) => applyEverything(layout))
        onClose()
      }}
      onDismiss={() => {
        curate((layout) => dismissRolePicker(layout))
        onClose()
      }}
    />
  )
}
