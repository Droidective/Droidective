import { Construction } from "lucide-react"
import { ActionForm } from "@/components/ActionForm"
import { AboutPane } from "@/components/AboutPane"
import { CatalogPane } from "@/components/CatalogPane"
import { HomeView } from "@/components/HomeView"
import {
  AppInfoPane,
  AppsPane,
  BugReportPane,
  CrashPane,
  DeepLinksPane,
  DeviceInfoPane,
  DevSettingsPane,
  EmulatorsPane,
  InstallAppPane,
  FileExplorerPane,
  LogcatPane,
  ManageAppPane,
  MeminfoPane,
  MirrorPane,
  NetspeedPane,
  PerformancePane,
  PermissionsPane,
  PrivateDnsPane,
  ReactotronPane,
  RestrictionsPane,
  RootStatusPane,
  SandboxPane,
  TerminalPane,
  WifiPane,
} from "@/components/panes"
import { ABOUT_TAB, CATALOG_TAB, HOME_TAB } from "@/lib/layout"
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
  disabledFeatures: string[]
  onSetEnabled: (id: string, enabled: boolean) => void
  onSetGroupEnabled: (members: FeatureSummary[], enabled: boolean) => void
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
  // The app's own screens, opened from the sidebar footer. No daemon serves
  // them, so they are matched before the registry lookup below.
  if (props.id === CATALOG_TAB) {
    return (
      <CatalogPane
        features={props.features}
        disabled={props.disabledFeatures}
        sidebarOrder={props.sidebarOrder}
        categoryOrder={props.categoryOrder}
        onSetEnabled={props.onSetEnabled}
        onSetGroupEnabled={props.onSetGroupEnabled}
      />
    )
  }
  if (props.id === ABOUT_TAB) return <AboutPane />
  if (props.feature === null) return <NotHere title={props.id} />

  const hostSide = hostPane(props.id, props.device)
  if (hostSide !== null) return hostSide

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
    case "scrcpy":
      return <MirrorPane device={props.device} />
    case "device-info":
      return <DeviceInfoPane device={props.device} />
    case "file-explorer":
      return <FileExplorerPane device={props.device} />
    case "crash-catcher":
      return <CrashPane device={props.device} />
    case "bug-report":
      return <BugReportPane device={props.device} packageId={props.packageId} />
    case "deep-link":
      return <DeepLinksPane device={props.device} packageId={props.packageId} />
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
    case "network-speed":
      return <NetspeedPane device={props.device} />
    case "install-app":
      return <InstallAppPane device={props.device} />
    case "app-info":
      return <AppInfoPane device={props.device} packageId={props.packageId} />
    case "permissions":
      return <PermissionsPane device={props.device} packageId={props.packageId} />
    case "meminfo":
      return <MeminfoPane device={props.device} packageId={props.packageId} />
    case "sandbox-browser":
      return <SandboxPane device={props.device} packageId={props.packageId} />
    case "app-management":
      return <ManageAppPane device={props.device} packageId={props.packageId} />
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

/**
 * The screens that run against *this* machine rather than a device.
 *
 * All three work with nothing connected, and each takes the selection
 * differently for a reason worth stating once: an emulator is a thing here and
 * the screen's whole job is launching one; a shell runs here and the selection
 * only decides what `ANDROID_SERIAL` says in the next tab; the Reactotron relay
 * listens here, and a device matters only for the reverse tunnel its waiting
 * screen offers.
 */
function hostPane(id: string, device: Device | null) {
  switch (id) {
    case "emulators":
      return <EmulatorsPane />
    case "terminal":
      return <TerminalPane serial={device?.serial ?? null} />
    case "reactotron":
      return <ReactotronPane device={device} />
    default:
      return null
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
