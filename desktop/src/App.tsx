import { useMemo } from "react"
import { Banner } from "@/components/Controls"
import { DeviceBar } from "@/components/DeviceBar"
import { NotificationPanel } from "@/components/NotificationPanel"
import { ToastOverlay } from "@/components/ToastOverlay"
import { WorkspaceShell } from "@/components/WorkspaceShell"
import { NotificationsProvider } from "@/hooks/useNotifications"
import { useSession } from "@/hooks/useSession"
import { sidebarFeatures } from "@/lib/sidebar"

/** Getting the daemon up, and the device bar over whatever it serves. */
export function App() {
  const session = useSession()
  const features = useMemo(() => sidebarFeatures(session.features), [session.features])

  if (session.status.state === "starting") {
    return <Splash>Starting droidectived…</Splash>
  }
  if (session.status.state === "failed") {
    return (
      <Splash>
        <Banner tone="error">
          <strong>droidectived would not start.</strong>
          <div className="mt-1 opacity-80">{session.status.message}</div>
        </Banner>
      </Splash>
    )
  }

  return (
    <NotificationsProvider>
      <div className="flex h-full flex-col">
        <DeviceBar
          devices={session.devices}
          devicesLoaded={session.devicesLoaded}
          selected={session.selected}
          onSelect={session.select}
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
          <WorkspaceShell features={features} device={session.selected} />
          <NotificationPanel />
        </div>
        <ToastOverlay />
      </div>
    </NotificationsProvider>
  )
}

function Splash({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full items-center justify-center p-8">
      <div className="max-w-md text-center text-text-secondary">{children}</div>
    </div>
  )
}
