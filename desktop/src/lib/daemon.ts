import { invoke } from "@tauri-apps/api/core"
import { listen, type UnlistenFn } from "@tauri-apps/api/event"

import type { RoleCatalogue } from "@/lib/roles"
import type {
  AppsResponse,
  CrashListResponse,
  DaemonError,
  DaemonStatus,
  Device,
  FeatureSummary,
  FieldValue,
  FileInfoResponse,
  FileOperation,
  FilePullResponse,
  FilesListResponse,
  ForegroundResponse,
  RootStatusResponse,
  RunResponse,
} from "@/lib/wire"

/**
 * The only way this app talks to `droidectived`.
 *
 * Every call goes through a Rust command rather than `fetch`, and that is not
 * incidental: the daemon refuses a request whose `Origin` is not loopback and
 * sends no CORS headers, so a webview cannot reach it directly — which is the
 * point. The bearer token stays in the Rust process.
 */

const STATUS_EVENT = "daemon://status"

export function daemonStatus(): Promise<DaemonStatus> {
  return invoke<DaemonStatus>("daemon_status")
}

/** Fires once when the daemon finishes starting, or fails to. */
export function onDaemonStatus(handler: (status: DaemonStatus) => void): Promise<UnlistenFn> {
  return listen<DaemonStatus>(STATUS_EVENT, (event) => {
    handler(event.payload)
  })
}

export function listDevices(): Promise<Device[]> {
  return invoke<Device[]>("list_devices")
}

export function listFeatures(): Promise<FeatureSummary[]> {
  return invoke<FeatureSummary[]>("list_features")
}

/** The role picker's catalogue — served, so the six lists never drift. */
export function listRoles(): Promise<RoleCatalogue> {
  return invoke<RoleCatalogue>("list_roles")
}

export function runAction(args: {
  featureId: string
  serial: string
  platform?: string
  fields?: Record<string, FieldValue>
}): Promise<RunResponse> {
  return invoke<RunResponse>("run_action", { args })
}

export function listApps(serial: string): Promise<AppsResponse> {
  return invoke<AppsResponse>("list_apps", { serial })
}

/** Everything `getprop` printed, as the daemon passed it through. */
export function deviceProps(serial: string): Promise<{ properties: Record<string, string> }> {
  return invoke<{ properties: Record<string, string> }>("device_props", { serial })
}

/** The frontmost app on the device, when there is one worth naming. */
/**
 * The process id an app is running under, or null when it is not running.
 *
 * Null is an answer rather than a failure: an app whose log you opened before
 * launching it is the ordinary case, and the log waits for it.
 */
export function logcatPid(serial: string, packageId: string): Promise<number | null> {
  return invoke<{ pid: number | null }>("logcat_pid", { serial, packageId }).then(
    (answer) => answer.pid ?? null,
  )
}

export function foregroundApp(serial: string): Promise<ForegroundResponse> {
  return invoke<ForegroundResponse>("foreground_app", { serial })
}

export function controlApp(args: {
  serial: string
  packageId: string
  action: string
}): Promise<RunResponse> {
  return invoke<RunResponse>("control_app", args)
}

/** Whether this device gives a root shell, and the signals behind the verdict. */
export function rootStatus(serial: string): Promise<RootStatusResponse> {
  return invoke<RootStatusResponse>("root_status", { serial })
}

export function listFiles(args: {
  serial: string
  path: string
  asRoot: boolean
}): Promise<FilesListResponse> {
  return invoke<FilesListResponse>("list_files", args)
}

/**
 * One mutation against the device's filesystem.
 *
 * Paths go over exactly as they came back from `ls`. Quoting them here would
 * be quoting them twice: ADBKit's `FileExplorerService` is where a path meets
 * a device shell, and it is the only place that escapes one.
 */
export function fileOperation(args: {
  serial: string
  op: FileOperation
  path: string
  destination?: string
  asRoot: boolean
}): Promise<RunResponse> {
  return invoke<RunResponse>("file_operation", {
    ...args,
    destination: args.destination ?? null,
  })
}

export function fileInfo(args: {
  serial: string
  path: string
  asRoot: boolean
}): Promise<FileInfoResponse> {
  return invoke<FileInfoResponse>("file_info", args)
}

/** Every crash the device has recorded, newest first. */
export function listCrashes(serial: string): Promise<CrashListResponse> {
  return invoke<CrashListResponse>("list_crashes", { serial })
}

/** Empties `logcat -b crash` on the device. */
export function clearCrashes(serial: string): Promise<RunResponse> {
  return invoke<RunResponse>("clear_crashes", { serial })
}

/** Pulls into ~/Downloads/Droidective and answers where it landed. */
export function pullFile(args: {
  serial: string
  path: string
  asRoot: boolean
}): Promise<FilePullResponse> {
  return invoke<FilePullResponse>("pull_file", args)
}

/**
 * Normalises whatever `invoke` rejected with.
 *
 * Rust serialises `DaemonError` as the daemon's own `{code,message,detail}`,
 * so the common case is already the right shape; this only has to cope with
 * the framework failing before our code runs.
 */
export function asDaemonError(error: unknown): DaemonError {
  if (typeof error === "object" && error !== null && "message" in error) {
    const shaped = error as Partial<DaemonError>
    return {
      code: shaped.code ?? "unknown",
      message: String(shaped.message),
      detail: shaped.detail ?? null,
    }
  }
  return { code: "unknown", message: String(error), detail: null }
}

// The host capabilities, the stream subscriptions and the per-device settings
// calls live next door, so this file stays inside its line budget;
// `@/lib/daemon` remains the one import for all of them.
export {
  backgroundAvailable,
  capturesFolder,
  copyText,
  exportText,
  hideQuickPanel,
  openUrl,
  postNotification,
  quitApp,
  revealPath,
  setBackgroundMode,
  setGlobalShortcuts,
  setTrayMenu,
  showMainWindow,
  toggleQuickPanel,
} from "@/lib/daemon-host"
export type { MirrorSession, Subscription, TerminalSession } from "@/lib/daemon-stream"
export {
  openTerminal,
  reactotronReverse,
  reactotronUnreverse,
  watchDevices,
  watchLogcat,
  watchMirror,
  watchNetspeed,
  watchPerformance,
  watchReactotron,
} from "@/lib/daemon-stream"
export {
  appInfo,
  connectWireless,
  createBugReport,
  deepLinks,
  detectTools,
  devSettings,
  disconnectWireless,
  emulatorAction,
  emulators,
  enableTcpip,
  launchDeepLink,
  pairWireless,
  writeDeepLinks,
  pickAndInstall,
  meminfo,
  permissions,
  privateDns,
  remountSystem,
  restrictions,
  pullApk,
  sandboxList,
  sandboxPull,
  setPermission,
  setPrivateDns,
  setWifiEnabled,
  connectWifi,
  wifi,
  writeDevSetting,
  writeRestriction,
} from "@/lib/daemon-settings"
export type {
  ApiSendResponse,
  AssertionOutcomeWire,
  RedirectHop,
  ResponseCookie,
  ResponseTiming,
} from "@/lib/daemon-api"
export {
  apiCancel,
  apiCode,
  apiCurl,
  apiExport,
  apiImport,
  apiSend,
  apiWorkspace,
  apiWrite,
} from "@/lib/daemon-api"
export type { RecordStatus, RecordWireOptions, StoppedRecording } from "@/lib/daemon-record"
export {
  discardDroppedFile,
  discardRecording,
  managedToolInstall,
  managedToolList,
  managedToolRemove,
  recordPause,
  recordResume,
  recordStart,
  recordStatus,
  recordStop,
  saveRecording,
  stageDroppedFile,
} from "@/lib/daemon-record"
export { customCommands, runCustomCommand, writeCustomCommands } from "@/lib/daemon-commands"
export {
  apkToolchain,
  convertAab,
  decompileApk,
  decompiledFile,
  inspectApk,
  installPath,
  installTool,
  managedTools,
  metroRunning,
  metroTargets,
  pickFile,
  pickFolder,
  rebuildDecompiled,
  searchDecompiled,
  signApk,
} from "@/lib/daemon-apk"
