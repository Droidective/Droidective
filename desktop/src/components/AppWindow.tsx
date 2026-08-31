import { Banner } from "@/components/Controls"
import { DeviceBarHost } from "@/components/DeviceBarHost"
import { NotificationPanel } from "@/components/NotificationPanel"
import { ToastOverlay } from "@/components/ToastOverlay"
import { WindowProviders } from "@/components/WindowProviders"
import { WorkspaceShell } from "@/components/WorkspaceShell"
import type { Session } from "@/hooks/useSession"
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
  // Every open tab, not only the exclusive ones: which of them matter is a
  // rule in `lib/workspaces.ts`, and the registry should not have an opinion.
  const openFeatures = workspace.workspace.groups.flatMap((group) => [...group.openTabs])

  return (
    <WindowProviders
      devices={session.devices}
      selected={session.selected}
      focusedFeature={focusedFeature}
      runOnAll={workspace.layout.runOnAll}
      openFeatures={openFeatures}
    >
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
    </WindowProviders>
  )
}
