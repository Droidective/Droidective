/**
 * One-time notices: shown once, then never again.
 *
 * The Mac keeps these in `@AppStorage` under their own keys rather than in
 * `LayoutState` — `hasSeenReactotronIntro` is not part of a window's layout and
 * no Settings screen shows it — so they live in their own namespace here too,
 * beside the layout rather than inside it.
 *
 * Every access is guarded: `localStorage` throws outright in a private window
 * and when site data is blocked, and a first-run notice is not worth failing a
 * render over. A throw reads as "not seen", which shows the notice one more
 * time — the safe direction for something whose whole job is to explain the
 * screen.
 */

const PREFIX = "droidective.seen."

/** A key for one notice, namespaced so it cannot collide with the layout's. */
export function seenKey(name: string): string {
  return `${PREFIX}${name}`
}

/** Whether this notice has been through already. */
export function hasSeen(storage: Storage | undefined, name: string): boolean {
  if (storage === undefined) return false
  try {
    return storage.getItem(seenKey(name)) === "true"
  } catch {
    return false
  }
}

/** Record that it has. Called on *any* dismissal, as the Mac does. */
export function markSeen(storage: Storage | undefined, name: string): void {
  if (storage === undefined) return
  try {
    storage.setItem(seenKey(name), "true")
  } catch {
    // Nothing to do: the notice will simply be offered again next launch.
  }
}
