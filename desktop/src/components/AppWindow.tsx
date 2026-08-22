import { Banner } from "@/components/Controls"
import { DeviceBarHost } from "@/components/DeviceBarHost"
import { NotificationPanel } from "@/components/NotificationPanel"
import { ToastOverlay } from "@/components/ToastOverlay"
import { WorkspaceShell } from "@/components/WorkspaceShell"
import type { Session } from "@/hooks/useSession"
import { TargetsProvider } from "@/hooks/useTargets"
import { TerminalCommandsProvider } from "@/hooks/useTerminalCommands"
import { useWindowChrome } from "@/hooks/useWindowChrome"
import type { FeatureSummary } from "@/lib/wire"

/**
 * The window once the daemon is up: the device bar over the workspace, with the
 * notification column beside it and the toasts on top.
 *
 * Nothing here decides anything — `useWindowChrome` owns the window's state and
 * `DeviceBarHost` and `WorkspaceShell` own their halves. This is the layout.
 */
export function AppWindow({
  session,
  features,
}: {
  session: Session
  features: FeatureSummary[]
}) {
  const { workspace, sidebar, focusedFeature } = useWindowChrome(features)

  return (
    <TargetsProvider
      devices={session.devices}
      selected={session.selected}
      focusedFeature={focusedFeature}
      runOnAll={workspace.layout.runOnAll}
    >
      {/* Above the workspace, because the menu's terminal commands are
          dispatched from the shell and the Terminal pane registers into it
          from inside a tab. */}
      <TerminalCommandsProvider>
      <div className="flex h-full flex-col">
        <DeviceBarHost
          session={session}
          workspace={workspace}
          focusedFeature={focusedFeature}
          sidebar={sidebar}
        />
        {session.error ? (
          <div className="px-3 pt-3">
            <Banner tone="error">{session.error.message}</Banner>
          </div>
        ) : null}
        {/* The panel is a sibling of the workspace, not an overlay: it is a
            persistent column, the way `NotificationPanelView` sits in the
            Mac's window. */}
        <div className="flex min-h-0 flex-1">
          <WorkspaceShell
            features={features}
            device={session.selected}
            workspace={workspace}
            sidebar={sidebar}
          />
          <NotificationPanel />
        </div>
        <ToastOverlay />
      </div>
      </TerminalCommandsProvider>
    </TargetsProvider>
  )
}
