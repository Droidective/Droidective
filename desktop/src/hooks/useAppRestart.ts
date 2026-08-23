import { useCallback, useState } from "react"
import { asDaemonError, controlApp, foregroundApp, listApps } from "@/lib/daemon"
import {
  CACHE_CLEAR_TIMEOUT_MS,
  clearAction,
  restartMessage,
  restartTarget,
  type ClearScope,
} from "@/lib/reactotron-restart"

export interface RestartOutcome {
  ok: boolean
  message: string
  /** Set when the target could not be worked out — the caller has to ask. */
  ask?: "no-client" | "no-match"
}

export interface AppRestart {
  busy: boolean
  /**
   * Restart the app the client belongs to, optionally wiping first. Returns
   * `ask` instead of acting when the target cannot be established.
   */
  restart: (args: { serial: string; clientName: string | null; scope: ClearScope }) => Promise<RestartOutcome>
  /** Restart a package the caller has already decided on. */
  restartPackage: (args: { serial: string; packageId: string; scope: ClearScope }) => Promise<RestartOutcome>
}

/**
 * Stop-and-relaunch an app, optionally wiping its cache or its data first.
 *
 * Every decision worth arguing about is in `lib/reactotron-restart.ts` — which
 * app, and what to say afterwards. What is left here is the sequence, and one
 * detail that only matters against a real device: the cache clear is raced
 * against a timeout, because `pm clear --cache-only` never returns on some
 * images and a restart that hangs forever is worse than one that says it could
 * not finish the clear.
 */
export function useAppRestart(): AppRestart {
  const [busy, setBusy] = useState(false)

  const restartPackage = useCallback(
    async (args: { serial: string; packageId: string; scope: ClearScope }): Promise<RestartOutcome> => {
      setBusy(true)
      try {
        const cleared = await clearFirst(args)
        // Stop then open, rather than the `restart` verb: the clear has to land
        // between the two, and a single verb gives nowhere to put it.
        await controlApp({ serial: args.serial, packageId: args.packageId, action: "stop" })
        const opened = await controlApp({
          serial: args.serial,
          packageId: args.packageId,
          action: "open",
        })
        if (!opened.ok) {
          return { ok: false, message: `Couldn't restart ${args.packageId}` }
        }
        return {
          ok: true,
          message: restartMessage({ packageId: args.packageId, scope: args.scope, cleared }),
        }
      } catch (thrown) {
        return { ok: false, message: asDaemonError(thrown).message }
      } finally {
        setBusy(false)
      }
    },
    [],
  )

  const restart = useCallback(
    async (args: { serial: string; clientName: string | null; scope: ClearScope }): Promise<RestartOutcome> => {
      setBusy(true)
      let target
      try {
        // Both lookups, then decide: the chain reads the installed list either
        // way, and asking for the foreground app costs one more call against a
        // device that is already answering.
        const [apps, front] = await Promise.all([
          listApps(args.serial),
          foregroundApp(args.serial),
        ])
        target = restartTarget({
          clientName: args.clientName,
          installed: apps.apps.map((app) => app.packageId),
          foreground: front.packageId ?? null,
        })
      } catch (thrown) {
        setBusy(false)
        return { ok: false, message: asDaemonError(thrown).message }
      } finally {
        setBusy(false)
      }
      if (target.kind === "ask") {
        return { ok: false, message: "Pick the app to restart.", ask: target.reason }
      }
      return restartPackage({ ...args, packageId: target.packageId })
    },
    [restartPackage],
  )

  return { busy, restart, restartPackage }
}

/**
 * Wipe before the relaunch, and report whether it worked rather than failing.
 *
 * The restart proceeds either way — `restartMessage` says which happened — so a
 * clear that hangs or refuses costs the caller a wording, not the restart.
 */
function clearFirst(args: {
  serial: string
  packageId: string
  scope: ClearScope
}): Promise<boolean> {
  if (args.scope === null) return Promise.resolve(true)
  const clear = controlApp({
    serial: args.serial,
    packageId: args.packageId,
    action: clearAction(args.scope),
  }).then(
    (result) => result.ok,
    () => false,
  )
  if (args.scope === "data") return clear
  // `pm clear --cache-only` never returns on some images, so this one is raced.
  // The adb child outlives the race — nothing here can kill it — which is
  // acceptable for a cache clear and is why the message says "didn't finish"
  // rather than "failed".
  const timeout = new Promise<boolean>((resolve) => {
    setTimeout(() => {
      resolve(false)
    }, CACHE_CLEAR_TIMEOUT_MS)
  })
  return Promise.race([clear, timeout])
}
