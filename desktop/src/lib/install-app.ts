import type { InstallOutcome } from "@/lib/wire"

/**
 * Install App's remembered choice and its messages — the Mac's
 * `installOpensApp` and `AppState.installAPKs` toasts, worded the same.
 */

const OPENS_APP = "droidective.installOpensApp"

/** "Open after installing", as it was last left. Off until someone ticks it. */
export function readOpensApp(): boolean {
  try {
    return localStorage.getItem(OPENS_APP) === "true"
  } catch {
    return false
  }
}

export function writeOpensApp(on: boolean): void {
  try {
    localStorage.setItem(OPENS_APP, String(on))
  } catch {
    // A storage that refuses a write only costs remembering the box.
  }
}

/** The headline toast: the Mac's, including "and opened" when it was. */
export function installHeadline(
  fileName: string,
  outcomes: readonly InstallOutcome[],
  opensApp: boolean,
): { ok: boolean; message: string } {
  const failed = outcomes.filter((outcome) => !outcome.ok)
  const total = outcomes.length
  if (failed.length === 0) {
    const verb = opensApp && openFailure(outcomes) === null ? "Installed and opened" : "Installed"
    return {
      ok: true,
      message: total === 1 ? `${verb} ${fileName}` : `${verb} ${fileName} on ${String(total)} devices`,
    }
  }
  const [only] = failed
  if (total === 1 && only !== undefined) {
    return { ok: false, message: `Couldn't install ${fileName} — ${only.message}` }
  }
  return {
    ok: false,
    message: `Installed ${fileName} on ${String(total - failed.length)}/${String(total)} devices — ${String(failed.length)} failed`,
  }
}

/** The first reason the app couldn't be opened where it installed, if any. */
export function openFailure(outcomes: readonly InstallOutcome[]): string | null {
  for (const outcome of outcomes) {
    if (outcome.ok && typeof outcome.openFailure === "string") return outcome.openFailure
  }
  return null
}

/** APK Studio reads one APK; a bundle is a container of them. */
export function opensInStudio(path: string): boolean {
  return path.toLowerCase().endsWith(".apk")
}
