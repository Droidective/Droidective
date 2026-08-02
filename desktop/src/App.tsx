import { useEffect, useState } from "react"
import { Boxes, ScrollText, Zap, type LucideIcon } from "lucide-react"
import { ActionsPane } from "@/components/ActionsPane"
import { AppsPane } from "@/components/AppsPane"
import { Banner } from "@/components/Controls"
import { DeviceBar } from "@/components/DeviceBar"
import { LogcatPane } from "@/components/LogcatPane"
import { useSession } from "@/hooks/useSession"
import { cn } from "@/lib/cn"

type Tab = "actions" | "apps" | "logcat"

export function App() {
  const session = useSession()
  const [tab, setTab] = useState<Tab>("actions")
  // Lifted out of the Apps pane: a `needsBundle` action in the palette needs
  // the same choice, so it cannot live inside one tab.
  const [packageId, setPackageId] = useState<string | null>(null)

  // A package id means nothing on a different device, so the choice is
  // dropped when the selection changes — here, where it is owned, rather than
  // in the pane that happens to set it.
  const serial = session.selected?.serial ?? null
  useEffect(() => {
    setPackageId(null)
  }, [serial])

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
    <div className="flex h-full flex-col">
      <DeviceBar
        devices={session.devices}
        devicesLoaded={session.devicesLoaded}
        selected={session.selected}
        onSelect={session.select}
      />

      <nav className="flex shrink-0 items-center gap-1 border-b border-border-subtle bg-bg-chrome px-3 py-1.5">
        <TabButton
          active={tab === "actions"}
          icon={Zap}
          onClick={() => {
            setTab("actions")
          }}
        >
          Actions
        </TabButton>
        <TabButton
          active={tab === "apps"}
          icon={Boxes}
          onClick={() => {
            setTab("apps")
          }}
        >
          Apps
        </TabButton>
        <TabButton
          active={tab === "logcat"}
          icon={ScrollText}
          onClick={() => {
            setTab("logcat")
          }}
        >
          Logcat
        </TabButton>
      </nav>

      {session.error ? (
        <div className="p-3">
          <Banner tone="error">{session.error.message}</Banner>
        </div>
      ) : null}

      {tab === "actions" ? (
        <ActionsPane
          features={session.features}
          device={session.selected}
          packageId={packageId}
        />
      ) : tab === "apps" ? (
        <AppsPane device={session.selected} selected={packageId} onSelect={setPackageId} />
      ) : (
        <LogcatPane device={session.selected} />
      )}
    </div>
  )
}

function TabButton({
  active,
  icon: Icon,
  onClick,
  children,
}: {
  active: boolean
  icon: LucideIcon
  onClick: () => void
  children: string
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex items-center gap-1.5 rounded-md px-2.5 py-1 transition-colors",
        active
          ? "bg-accent/15 text-text-primary"
          : "text-text-secondary hover:bg-white/[0.05] hover:text-text-primary",
      )}
    >
      <Icon size={14} className={active ? "text-accent" : "text-text-secondary"} />
      {children}
    </button>
  )
}

function Splash({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full items-center justify-center p-8">
      <div className="max-w-md text-center text-text-secondary">{children}</div>
    </div>
  )
}
