import { Construction } from "lucide-react"
import { ActionForm } from "@/components/ActionForm"
import { AboutPane } from "@/components/AboutPane"
import { CatalogPane } from "@/components/CatalogPane"
import { HomeView } from "@/components/HomeView"
import {
  AabConvertPane,
  ApiClientPane,
  ApkInspectorPane,
  ApkSignPane,
  ApkStudioPane,
  AppInfoPane,
  AppsPane,
  BugReportPane,
  ConnectionHubPane,
  CrashPane,
  CustomCommandsPane,
  DecompilePane,
  DeepLinksPane,
  DeviceInfoPane,
  DevSettingsPane,
  EmulatorsPane,
  InstallAppPane,
  JsConsolePane,
  FileExplorerPane,
  LogcatPane,
  ManageAppPane,
  MeminfoPane,
  MirrorPane,
  MirrorWallPane,
  NetspeedPane,
  PerformancePane,
  PermissionsPane,
  PrivateDnsPane,
  ReactNativeHubPane,
  ReactotronPane,
  RestrictionsPane,
  RootStatusPane,
  SandboxPane,
  SimulateHubPane,
  TerminalPane,
  WifiPane,
  WirelessAdbPane,
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

  const hostSide = hostPane(props)
  if (hostSide !== null) return hostSide
  const perApp = appPane(props)
  if (perApp !== null) return perApp

  switch (props.id) {
    case "apps":
      return (
        <AppsPane
          device={props.device}
          selected={props.packageId}
          onSelect={props.onSelectPackage}
        />
      )
    case "aab-convert":
      return <AabConvertPane device={props.device} />
    case "custom-commands":
      return <CustomCommandsPane device={props.device} packageId={props.packageId} />
    case "logcat":
      return (
        <LogcatPane
          device={props.device}
          packageId={props.packageId}
          onSelectPackage={props.onSelectPackage}
        />
      )
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
    case "simulate":
      return <SimulateHubPane device={props.device} features={props.features} />
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
 * The screens scoped to one *app* as well as one device.
 *
 * All five take the Apps tab's selection and show `NoBundle` without it, so
 * they are one group rather than five near-identical cases — and keeping them
 * out of the switch above is what keeps `FeaturePane` a routing table.
 *
 * Deliberately declared before `hostPane`: `hints.test.ts` cuts the file there
 * to decide which screens need a connect-a-device line, and these do.
 */
function appPane({ id, device, packageId }: FeaturePaneProps) {
  switch (id) {
    case "app-info":
      return <AppInfoPane device={device} packageId={packageId} />
    case "permissions":
      return <PermissionsPane device={device} packageId={packageId} />
    case "meminfo":
      return <MeminfoPane device={device} packageId={packageId} />
    case "sandbox-browser":
      return <SandboxPane device={device} packageId={packageId} />
    case "app-management":
      return <ManageAppPane device={device} packageId={packageId} />
    default:
      return null
  }
}

/**
 * The screens that run against *this* machine rather than a device.
 *
 * Each works with nothing connected, and each takes the selection differently
 * for a reason worth stating once: an emulator is a thing here and the screen's
 * whole job is launching one; a shell runs here and the selection only decides
 * what `ANDROID_SERIAL` says in the next tab; the Reactotron relay listens here,
 * and a device matters only for the reverse tunnel its waiting screen offers.
 *
 * What they have in common is what `hints.test.ts` cuts on: none of them can
 * reach the connect-a-device empty state, so a line for it would be dead text.
 */
function hostPane({ id, device, packageId, onOpen }: FeaturePaneProps) {
  switch (id) {
    case "emulators":
      return <EmulatorsPane />
    case "terminal":
      return <TerminalPane serial={device?.serial ?? null} />
    case "reactotron":
      return <ReactotronPane device={device} />
    case "js-console":
      // Metro is a process on this machine, so the console connects with no
      // device at all; the selection only decides which device gets the
      // `adb reverse` that lets it reach Metro.
      return <JsConsolePane device={device} />
    case "apk-inspector":
      // Device-free: an APK is a file on this machine, so both work with
      // nothing connected.
      return <ApkInspectorPane />
    case "apk-sign":
      return <ApkSignPane />
    case "apk-decompile":
      // Device-free like the other two: an APK is a file on this machine.
      return <DecompilePane />
    case "apk-studio":
      // The hub over the three above. Reachable on its own too — the members
      // fold into it once this app has the screen (`lib/hubs.ts`).
      return <ApkStudioPane />
    case "api-client":
      // Device-free by construction: nothing on this screen touches adb, which
      // is why it draws with nothing connected — the Mac's own reason for
      // keeping it out of `NoDeviceView`.
      return <ApiClientPane />
    case "wireless-adb":
      // Host-side: it is about the devices themselves, so it works — and is
      // most wanted — with nothing selected in the bar.
      return <WirelessAdbPane />
    case "connection":
      // The hub over the wireless screen, and host-side for the same reason:
      // pairing a device is what you do when none is attached. Its
      // device-scoped sections say so individually rather than the screen
      // refusing to draw, which is how the Mac's `NetworkConnectionView`
      // behaves.
      return <ConnectionHubPane device={device} />
    case "react-native":
      // Metro runs on *this* machine and the deep links are stored here, so
      // the screen draws with nothing attached and each section says what it
      // needs — the Mac's `ReactNativeView` puts "Connect a device to use
      // these" under the cards rather than replacing the pane. Same reasoning
      // as `js-console` above.
      return <ReactNativeHubPane device={device} packageId={packageId} onOpen={onOpen} />
    case "mirror-wall":
      // Host-side by the same logic as the others: the wall picks its own
      // devices from its header and never follows the bar's selection.
      return <MirrorWallPane />
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
