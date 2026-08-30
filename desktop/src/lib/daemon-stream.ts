/**
 * The `/v1/stream` subscriptions.
 *
 * Split out of `daemon.ts` when it outgrew its line budget, and split *here*
 * because they share one shape the request/response calls do not: a Tauri
 * `Channel` that keeps delivering until it is stopped. They are re-exported
 * from `@/lib/daemon`, which stays the one import for everything that talks to
 * the daemon.
 *
 * The correlation ids come from Rust, never from here — the daemon refuses a
 * duplicate id, and letting a page choose them would make that refusal a bug
 * the UI could trigger.
 */

import { Channel, invoke } from "@tauri-apps/api/core"
import type {
  Device,
  LogLine,
  MirrorFrame,
  NetSample,
  PerfSample,
  PtyChunk,
  ReactotronFrame,
  ReactotronReverseResponse,
  StreamUpdate,
} from "@/lib/wire"

/** A live subscription. Always `stop()` it when the view goes away. */
export interface Subscription {
  id: number
  stop: () => Promise<void>
}

/**
 * Every subscription this window has open.
 *
 * Kept because background mode has to end all of them at once: the Mac's
 * `AppState.enterBackground` walks its open features and stops each one's work,
 * and the equivalent here is that nothing keeps streaming out of a device into
 * a window nobody can see. A window's worth of live subscriptions is a handful,
 * so a Set is the whole data structure this needs.
 */
const live = new Set<Subscription>()

/**
 * Stops everything, for a window that has just been hidden.
 *
 * Deliberately a stop and not a pause: the Mac stops this work rather than
 * suspending it — terminal shells included — and says so in Settings. A screen
 * re-entered afterwards subscribes again the way it did the first time.
 */
export async function stopAllStreams(): Promise<void> {
  await Promise.all([...live].map((subscription) => subscription.stop()))
}

async function subscribe<Item>(
  command:
    | "open_terminal"
    | "watch_devices"
    | "watch_logcat"
    | "watch_mirror"
    | "watch_netspeed"
    | "watch_performance"
    | "watch_reactotron",
  args: Record<string, unknown>,
  onUpdate: (update: StreamUpdate<Item>) => void,
): Promise<Subscription> {
  const channel = new Channel<StreamUpdate<Item>>()
  // Tauri's Channel is an IPC handle, not an EventTarget; `onmessage` is
  // the whole API it offers.
  // oxlint-disable-next-line unicorn/prefer-add-event-listener
  channel.onmessage = onUpdate
  const id = await invoke<number>(command, { ...args, onEvent: channel })
  const subscription: Subscription = {
    id,
    stop: async () => {
      // Detach first: a batch already in flight must not reach a view that
      // has unmounted.
      // oxlint-disable-next-line unicorn/prefer-add-event-listener
      channel.onmessage = () => {}
      // Before the await, so a pane unmounting after the background teardown
      // already stopped its stream does not send a second request for an id
      // the daemon has forgotten.
      if (!live.delete(subscription)) return
      await invoke("stop_watching", { id })
    },
  }
  live.add(subscription)
  return subscription
}

export function watchDevices(
  onUpdate: (update: StreamUpdate<Device>) => void,
): Promise<Subscription> {
  return subscribe("watch_devices", {}, onUpdate)
}

/**
 * One device's live log.
 *
 * `pid` narrows it to a single process through `adb logcat --pid`, so the
 * device filters at the source: the ring buffer then holds only that app's
 * lines, where a client-side filter over a mixed buffer would let a chatty
 * neighbour evict them first. Null is the whole device, which is what the log
 * opens as. Resolving a package to a pid is `logcatPid`.
 */
export function watchLogcat(
  serial: string,
  pid: number | null,
  onUpdate: (update: StreamUpdate<LogLine>) => void,
): Promise<Subscription> {
  return subscribe("watch_logcat", { serial, pid }, onUpdate)
}

/**
 * One performance sample a second until stopped.
 *
 * `processes` is opt-in because it costs two extra `dumpsys` calls per sample
 * — enough that leaving it on would show up in the numbers being measured.
 */
export function watchPerformance(
  args: { serial: string; packageId: string | null; processes: boolean },
  onUpdate: (update: StreamUpdate<PerfSample>) => void,
): Promise<Subscription> {
  return subscribe("watch_performance", args, onUpdate)
}

/** Live `/proc/net/dev` throughput, one sample a second. */
export function watchNetspeed(
  serial: string,
  onUpdate: (update: StreamUpdate<NetSample>) => void,
): Promise<Subscription> {
  return subscribe("watch_netspeed", { serial }, onUpdate)
}

/**
 * Everything the Reactotron relay sees.
 *
 * Subscribing is also what *starts* the relay, and the last unsubscribe stops
 * it — so a mounted pane is a listening relay, and there is no separate switch
 * for the two to disagree about.
 */
export function watchReactotron(
  onUpdate: (update: StreamUpdate<ReactotronFrame>) => void,
): Promise<Subscription> {
  return subscribe("watch_reactotron", {}, onUpdate)
}

/**
 * Opens `adb reverse tcp:<port> tcp:<port>` so each device's own localhost
 * reaches the relay.
 *
 * The port is the one the relay reported binding rather than a constant: a
 * tunnel to a port nothing is listening on is the failure that reads as the
 * whole feature being broken.
 */
export function reactotronReverse(
  serials: string[],
  port: number | null,
): Promise<ReactotronReverseResponse> {
  return invoke("reactotron_reverse", { serials, port })
}

export function reactotronUnreverse(
  serials: string[],
  port: number | null,
): Promise<ReactotronReverseResponse> {
  return invoke("reactotron_unreverse", { serials, port })
}

/** One open terminal, and everything that can be sent into it. */
export interface TerminalSession extends Subscription {
  /** Keystrokes. Takes a base64 string — see `encodeInput`. */
  send: (data: string) => Promise<void>
  resize: (columns: number, rows: number) => Promise<void>
}

/**
 * Opens a shell on a pseudo-terminal.
 *
 * `serial` only exports `ANDROID_SERIAL` into the shell, so adb inside it
 * targets that device without `-s` — the way the Mac scopes a terminal tab. It
 * is nullable because a terminal has to open with nothing connected.
 *
 * The size goes on the open rather than as a resize afterwards: a shell that
 * printed its first prompt at 80 columns and then re-wrapped is a visible
 * flicker on every tab.
 */
export async function openTerminal(
  args: { serial: string | null; columns: number; rows: number },
  onUpdate: (update: StreamUpdate<PtyChunk>) => void,
): Promise<TerminalSession> {
  const subscription = await subscribe<PtyChunk>("open_terminal", args, onUpdate)
  const id = subscription.id
  return {
    ...subscription,
    send: (data: string) => invoke("write_terminal", { id, data }),
    resize: (columns: number, rows: number) =>
      invoke("resize_terminal", { id, columns, rows }),
  }
}

/** A live mirror, and everything that can be sent into it. */
export interface MirrorSession extends Subscription {
  /** A control message. Takes base64 — see `encodeControl`. */
  send: (data: string) => Promise<void>
}

/**
 * Mirrors a device's screen.
 *
 * The frames arrive already framed for `VideoDecoder`: a `config` first, then
 * Annex-B keyframes and deltas. `lib/mirror.ts` holds the rules for feeding
 * them to a decoder, and there are three — configure first, wait for a keyframe
 * after a gap, size from the frames — because each one fails quietly.
 *
 * Stopping is what tears the scrcpy server and its `adb forward` down, so a
 * view that unmounts without stopping leaks a tunnel into the long-lived adb
 * server.
 */
export async function watchMirror(
  serial: string,
  quality: { maxSize: number; maxFps: number },
  onUpdate: (update: StreamUpdate<MirrorFrame>) => void,
): Promise<MirrorSession> {
  const subscription = await subscribe<MirrorFrame>(
    "watch_mirror",
    // Resolved here rather than by the daemon: the Mirror Wall steps quality
    // down as tiles are added, and only this side knows how many it is drawing.
    { serial, maxSize: quality.maxSize, maxFps: quality.maxFps },
    onUpdate,
  )
  const id = subscription.id
  return {
    ...subscription,
    send: (data: string) => invoke("write_mirror", { id, data }),
  }
}
