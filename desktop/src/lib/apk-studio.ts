/**
 * APK Studio's tabs, as a table.
 *
 * A table rather than markup so the set is one thing to read and one thing to
 * test against the registry: each tab is a feature the hub folded in, and a tab
 * that named an id the registry does not absorb would be a tab the Mac's studio
 * does not have.
 */

/** Which tab is showing. */
export type StudioTab = "inspect" | "decompile" | "sign"

export interface StudioTabDef {
  id: StudioTab
  title: string
  /**
   * The registry feature this tab *is* — the same screen the standalone
   * feature shows, handed the studio's APK.
   */
  featureID: string
}

/**
 * In the order the Mac's studio shows them, which is the order the work
 * happens in: read it, take it apart, then sign what you built.
 */
export const STUDIO_TABS: readonly StudioTabDef[] = [
  { id: "inspect", title: "Inspect", featureID: "apk-inspector" },
  { id: "decompile", title: "Decompile", featureID: "apk-decompile" },
  { id: "sign", title: "Sign", featureID: "apk-sign" },
]

/** The hub's own feature id. */
export const APK_STUDIO_ID = "apk-studio"

/**
 * An APK another screen asked the studio to open — Install App's "Open in APK
 * Studio", the Mac's `openInApkStudio`.
 *
 * The studio is a kept-alive tab, so it may already be mounted when the ask
 * comes: a mounted studio listens, and one that mounts afterwards reads what
 * was left for it. Reading does not consume — a render can run twice — so the
 * studio clears it when it starts listening instead.
 */
let pendingApk: string | null = null
const studioListeners = new Set<(path: string) => void>()

export function openInStudio(path: string): void {
  if (studioListeners.size === 0) {
    pendingApk = path
    return
  }
  for (const listener of studioListeners) listener(path)
}

/** What was handed over before any studio was mounted to hear it. */
export function pendingStudioApk(): string | null {
  return pendingApk
}

/** Hear every later hand-over; the pending one has been read by then. */
export function listenForStudioApk(listener: (path: string) => void): () => void {
  pendingApk = null
  studioListeners.add(listener)
  return () => {
    studioListeners.delete(listener)
  }
}
