/**
 * Reading and writing one device's settings.
 *
 * Split out of `daemon.ts` when it outgrew its line budget: these are the
 * calls behind Developer Settings, System Restrictions, Wi-Fi and Private DNS.
 * They are re-exported from `@/lib/daemon`, which stays the one import for
 * everything that talks to the daemon.
 */

import { invoke } from "@tauri-apps/api/core"
import type {
  AppInfoResponse,
  EmulatorAction,
  EmulatorsResponse,
  AppPullResponse,
  DevSettingsResponse,
  DnsMode,
  DnsResponse,
  MemInfoResponse,
  PermissionsResponse,
  RestrictionKey,
  RestrictionsResponse,
  RunResponse,
  SandboxResponse,
  WifiResponse,
} from "@/lib/wire"

/** Every Developer Options row, definition and current value together. */
export function devSettings(serial: string): Promise<DevSettingsResponse> {
  return invoke<DevSettingsResponse>("dev_settings", { serial })
}

/**
 * Writes one Developer Options row.
 *
 * `on` for a toggle, `value` for a scale — which one is sent is what picks the
 * table the daemon looks the id up in, so exactly one of them must be.
 */
export function writeDevSetting(args: {
  serial: string
  id: string
  on?: boolean
  value?: number
}): Promise<RunResponse> {
  return invoke<RunResponse>("write_dev_setting", {
    serial: args.serial,
    id: args.id,
    on: args.on ?? null,
    value: args.value ?? null,
  })
}

/** The dev-time restrictions, plus whether the root-only half is reachable. */
export function restrictions(serial: string): Promise<RestrictionsResponse> {
  return invoke<RestrictionsResponse>("restrictions", { serial })
}

export function writeRestriction(args: {
  serial: string
  key: RestrictionKey
  on: boolean
}): Promise<RunResponse> {
  return invoke<RunResponse>("write_restriction", args)
}

/** The connection, the saved networks, and whether passwords were readable. */
export function wifi(serial: string): Promise<WifiResponse> {
  return invoke<WifiResponse>("wifi", { serial })
}

export function setWifiEnabled(serial: string, enabled: boolean): Promise<RunResponse> {
  return invoke<RunResponse>("write_wifi", {
    serial,
    enabled,
    ssid: null,
    security: null,
    password: null,
  })
}

/**
 * Joins a network.
 *
 * The SSID and password travel verbatim; `WifiService.connect` is where they
 * meet a device shell and the only place that quotes them. `security` is a
 * keyword rather than a value, so the daemon checks it against a closed set.
 */
export function connectWifi(args: {
  serial: string
  ssid: string
  security: string
  password: string
}): Promise<RunResponse> {
  return invoke<RunResponse>("write_wifi", { ...args, enabled: null })
}

export function privateDns(serial: string): Promise<DnsResponse> {
  return invoke<DnsResponse>("private_dns", { serial })
}

export function setPrivateDns(args: {
  serial: string
  mode: DnsMode
  hostname?: string
}): Promise<RunResponse> {
  return invoke<RunResponse>("write_private_dns", {
    serial: args.serial,
    mode: args.mode,
    hostname: args.hostname ?? null,
  })
}

/** `mount -o rw,remount /` through `su`. Root-only, and not a toggle. */
export function remountSystem(serial: string): Promise<RunResponse> {
  return invoke<RunResponse>("write_restriction", { serial, key: "remount", on: null })
}

// MARK: - the per-app screens

/** Version, SDK levels and install dates for the chosen package. */
export function appInfo(serial: string, packageId: string): Promise<AppInfoResponse> {
  return invoke<AppInfoResponse>("app_info", { serial, packageId })
}

export function permissions(serial: string, packageId: string): Promise<PermissionsResponse> {
  return invoke<PermissionsResponse>("permissions", { serial, packageId })
}

export function setPermission(args: {
  serial: string
  packageId: string
  permission: string
  grant: boolean
}): Promise<RunResponse> {
  return invoke<RunResponse>("set_permission", args)
}

export function meminfo(serial: string, packageId: string): Promise<MemInfoResponse> {
  return invoke<MemInfoResponse>("meminfo", { serial, packageId })
}

/** One directory inside a debuggable app's sandbox, via `run-as`. */
export function sandboxList(args: {
  serial: string
  packageId: string
  path: string
}): Promise<SandboxResponse> {
  return invoke<SandboxResponse>("sandbox_list", args)
}

/** Pulls one sandbox file into ~/Downloads/Droidective. */
export function sandboxPull(args: {
  serial: string
  packageId: string
  path: string
}): Promise<AppPullResponse> {
  return invoke<AppPullResponse>("sandbox_pull", args)
}

/** Pulls the package's APK, and its splits if it has any. */
export function pullApk(serial: string, packageId: string): Promise<AppPullResponse> {
  return invoke<AppPullResponse>("pull_apk", { serial, packageId })
}

// MARK: - the Android emulator

/** Every AVD on this machine, and whether the emulator binary is here. */
export function emulators(): Promise<EmulatorsResponse> {
  return invoke<EmulatorsResponse>("emulators")
}

/**
 * Launch, cold-boot, wipe, relaunch or stop one AVD.
 *
 * `stop` identifies by serial and the rest by name; `relaunch` needs both,
 * since it stops one instance and boots the same AVD again. The daemon
 * refuses a request missing what its verb needs.
 */
export function emulatorAction(args: {
  action: EmulatorAction
  avd?: string
  serial?: string
}): Promise<RunResponse> {
  return invoke<RunResponse>("emulator_action", {
    action: args.action,
    avd: args.avd ?? null,
    serial: args.serial ?? null,
  })
}
