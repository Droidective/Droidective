import { Channel, invoke } from "@tauri-apps/api/core"
import { listen, type UnlistenFn } from "@tauri-apps/api/event"
import type {
  AppsResponse,
  DaemonError,
  DaemonStatus,
  Device,
  FeatureSummary,
  FieldValue,
  LogLine,
  RunResponse,
  StreamUpdate,
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

export function controlApp(args: {
  serial: string
  packageId: string
  action: string
}): Promise<RunResponse> {
  return invoke<RunResponse>("control_app", args)
}

/**
 * Host capabilities, not daemon calls — but they arrive the same way and fail
 * the same way, so they live beside the rest rather than in a second module
 * with its own error shape.
 */
export function copyText(text: string): Promise<void> {
  return invoke("copy_text", { text })
}

export function revealPath(path: string): Promise<void> {
  return invoke("reveal_path", { path })
}

/** A live subscription. Always `stop()` it when the view goes away. */
export interface Subscription {
  id: number
  stop: () => Promise<void>
}

async function subscribe<Item>(
  command: "watch_devices" | "watch_logcat",
  args: Record<string, unknown>,
  onUpdate: (update: StreamUpdate<Item>) => void,
): Promise<Subscription> {
  const channel = new Channel<StreamUpdate<Item>>()
  // Tauri's Channel is an IPC handle, not an EventTarget; `onmessage` is
  // the whole API it offers.
  // oxlint-disable-next-line unicorn/prefer-add-event-listener
  channel.onmessage = onUpdate
  const id = await invoke<number>(command, { ...args, onEvent: channel })
  return {
    id,
    stop: async () => {
      // Detach first: a batch already in flight must not reach a view that
      // has unmounted.
      // oxlint-disable-next-line unicorn/prefer-add-event-listener
      channel.onmessage = () => {}
      await invoke("stop_watching", { id })
    },
  }
}

export function watchDevices(
  onUpdate: (update: StreamUpdate<Device>) => void,
): Promise<Subscription> {
  return subscribe("watch_devices", {}, onUpdate)
}

export function watchLogcat(
  serial: string,
  onUpdate: (update: StreamUpdate<LogLine>) => void,
): Promise<Subscription> {
  return subscribe("watch_logcat", { serial, filter: null }, onUpdate)
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
