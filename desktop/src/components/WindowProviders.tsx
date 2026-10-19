import { DropTargetProvider } from "@/hooks/useDropTarget"
import { RemoteLinkProvider } from "@/hooks/useRemoteLink"
import { TargetsProvider } from "@/hooks/useTargets"
import { TerminalCommandsProvider } from "@/hooks/useTerminalCommands"
import { WindowsProvider } from "@/hooks/useWindows"
import type { Device, FeatureSummary } from "@/lib/wire"

/**
 * The contexts a window's contents sit inside.
 *
 * Gathered so `AppWindow` stays a layout: which providers wrap it is a fact
 * about the app, and the nesting order matters in exactly one place — the
 * terminal commands have to be above the workspace, because the menu
 * dispatches them from the shell and the Terminal pane registers into them
 * from inside a tab.
 */
export function WindowProviders({
  devices,
  selected,
  features,
  focusedFeature,
  runOnAll,
  openFeatures,
  children,
}: {
  devices: Device[]
  selected: Device | null
  /** The registry, for the features that ask first on a tailnet phone. */
  features: FeatureSummary[]
  focusedFeature: FeatureSummary | null
  runOnAll: boolean
  openFeatures: string[]
  children: React.ReactNode
}) {
  return (
    <WindowsProvider serial={selected?.serial ?? null} openFeatures={openFeatures}>
      <TargetsProvider
        devices={devices}
        selected={selected}
        focusedFeature={focusedFeature}
        runOnAll={runOnAll}
      >
        <RemoteLinkProvider features={features} devices={devices}>
          <TerminalCommandsProvider>
            <DropTargetProvider>{children}</DropTargetProvider>
          </TerminalCommandsProvider>
        </RemoteLinkProvider>
      </TargetsProvider>
    </WindowsProvider>
  )
}
