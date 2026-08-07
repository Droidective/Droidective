import { Construction } from "lucide-react"
import { ActionForm } from "@/components/ActionForm"
import { HomeView } from "@/components/HomeView"
import {
  AppsPane,
  CrashPane,
  DeviceInfoPane,
  DevSettingsPane,
  FileExplorerPane,
  LogcatPane,
  PerformancePane,
  PrivateDnsPane,
  RestrictionsPane,
  RootStatusPane,
  WifiPane,
} from "@/components/panes"
import { HOME_TAB } from "@/lib/layout"
import { isRunnable, type Device, type FeatureSummary } from "@/lib/wire"

export interface FeaturePaneProps {
  id: string
  feature: FeatureSummary | null
  features: FeatureSummary[]
  device: Device | null
  packageId: string | null
  onSelectPackage: (packageId: string | null) => void
  onOpen: (id: string) => void
  sidebarOrder: string[]
  categoryOrder: string[]
  favorites: string[]
}

/**
 * What a tab shows.
 *
 * Full-screen views get a hand-built pane; every action kind renders from its
 * registry fields, which is why most of the registry works here without a line
 * of per-feature code. Anything else says so plainly — the Mac's "Coming Soon"
 * rather than an empty pane that reads as broken.
 */
export function FeaturePane(props: FeaturePaneProps) {
  if (props.id === HOME_TAB) {
    return (
      <HomeView
        features={props.features}
        sidebarOrder={props.sidebarOrder}
        categoryOrder={props.categoryOrder}
        favorites={props.favorites}
        onOpen={props.onOpen}
      />
    )
  }
  if (props.feature === null) return <NotHere title={props.id} />

  switch (props.id) {
    case "apps":
      return (
        <AppsPane
          device={props.device}
          selected={props.packageId}
          onSelect={props.onSelectPackage}
        />
      )
    case "logcat":
      return <LogcatPane device={props.device} />
    case "device-info":
      return <DeviceInfoPane device={props.device} />
    case "file-explorer":
      return <FileExplorerPane device={props.device} />
    case "crash-catcher":
      return <CrashPane device={props.device} />
    case "performance":
      return <PerformancePane device={props.device} packageId={props.packageId} />
    case "root-status":
      return <RootStatusPane device={props.device} />
    case "dev-settings":
      return <DevSettingsPane device={props.device} />
    case "system-restrictions":
      return <RestrictionsPane device={props.device} />
    case "wifi":
      return <WifiPane device={props.device} />
    case "private-dns":
      return <PrivateDnsPane device={props.device} />
    default:
      return isRunnable(props.feature) ? (
        <ActionForm
          feature={props.feature}
          device={props.device}
          packageId={props.packageId}
        />
      ) : (
        <NotHere title={props.feature.title} subtitle={props.feature.subtitle} />
      )
  }
}

function NotHere({ title, subtitle }: { title: string; subtitle?: string | null }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
      <Construction size={22} className="text-text-tertiary" />
      <h2 className="text-[15px] text-text-primary">{title}</h2>
      {subtitle ? <p className="text-text-secondary">{subtitle}</p> : null}
      <p className="max-w-sm text-text-tertiary">
        This screen has not been built for Windows and Linux yet. `docs/desktop-parity.md` tracks
        what it needs.
      </p>
    </div>
  )
}
