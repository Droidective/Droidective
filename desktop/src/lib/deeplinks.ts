import type { DeepLink } from "@/lib/wire"

/**
 * Editing one app's saved deep links.
 *
 * The list is the unit: the screen holds it, edits it here, and writes the whole
 * thing back — so these are the only three things that can happen to it, and
 * they are worth testing away from a dialog.
 */

/** Whether the editor's Save is worth enabling — the Mac's own rule. */
export function isSubmittable(url: string): boolean {
  return url.trim() !== ""
}

/**
 * An id for a new link.
 *
 * `randomUUID` needs a secure context, which a webview served from
 * `tauri://localhost` is — but a fallback costs one line and beats a screen
 * that throws on a platform where it is not exposed.
 */
export function linkId(): string {
  const uuid = globalThis.crypto?.randomUUID?.()
  return uuid ?? `link-${String(Date.now())}-${String(Math.floor(Math.random() * 1e6))}`
}

/**
 * The list with a link added or replaced.
 *
 * Replaced *in place* when the id already exists: an edit that moved a row to
 * the bottom would reorder a list nobody asked to reorder. A new one appends,
 * as the Mac's `links.append` does.
 */
export function upsert(links: readonly DeepLink[], link: DeepLink): DeepLink[] {
  const index = links.findIndex((existing) => existing.id === link.id)
  if (index === -1) return [...links, link]
  return links.map((existing, at) => (at === index ? link : existing))
}

export function removeLink(links: readonly DeepLink[], id: string): DeepLink[] {
  return links.filter((link) => link.id !== id)
}

/** Trimmed on the way in, so a pasted url does not carry its whitespace. */
export function draftLink(
  id: string,
  label: string,
  url: string,
  createdAt: number,
): DeepLink {
  return { id, label: label.trim(), url: url.trim(), createdAt }
}

/**
 * How a launch across several devices reads as one line.
 *
 * One device keeps its own message, which is where adb's reason for refusing a
 * scheme shows up. Several become a count naming the failures, because the
 * interesting case is "it worked on two of three".
 */
export function launchSummary(
  outcomes: readonly { serial: string; ok: boolean; message: string }[],
): { ok: boolean; message: string } {
  const [only] = outcomes
  if (outcomes.length === 0) return { ok: false, message: "No device connected." }
  if (outcomes.length === 1 && only !== undefined) return { ok: only.ok, message: only.message }
  const failed = outcomes.filter((outcome) => !outcome.ok)
  if (failed.length === 0) {
    return { ok: true, message: `Launched on ${String(outcomes.length)} devices` }
  }
  return {
    ok: false,
    message: `Launched on ${String(outcomes.length - failed.length)} of ${String(outcomes.length)} — failed on ${failed
      .map((outcome) => outcome.serial)
      .join(", ")}`,
  }
}
