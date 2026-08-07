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
  DevSettingsResponse,
  DnsMode,
  DnsResponse,
  RestrictionKey,
  RestrictionsResponse,
  RunResponse,
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
