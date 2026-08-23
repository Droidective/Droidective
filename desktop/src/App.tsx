import { useMemo } from "react"
import { AppWindow } from "@/components/AppWindow"
import { Banner } from "@/components/Controls"
import { AppearanceProvider } from "@/hooks/useAppearance"
import { NotificationsProvider } from "@/hooks/useNotifications"
import { useSession } from "@/hooks/useSession"
import { ToolchainProvider } from "@/hooks/useToolchain"
import { sidebarFeatures } from "@/lib/sidebar"

/** Getting the daemon up, and the window over whatever it serves. */
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
    <AppearanceProvider>
      <NotificationsProvider>
        <ToolchainProvider>
          <AppWindow session={session} features={features} />
        </ToolchainProvider>
      </NotificationsProvider>
    </AppearanceProvider>
  )
}

function Splash({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full items-center justify-center p-8">
      <div className="max-w-md text-center text-text-secondary">{children}</div>
    </div>
  )
}
