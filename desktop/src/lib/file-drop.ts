/**
 * What a file dropped on the window should do.
 *
 * The Mac has two: an APK or a bundle dropped anywhere installs, and a file
 * dropped on the File Explorer is pushed to the directory it is showing. Which
 * of the two a drop means is decided here — pure, so the rule can be tested
 * without a drag, which is the one gesture no synthetic event can produce in a
 * webview.
 */

/** The formats `AppPackageFormat` accepts, lowercased and without the dot. */
export const INSTALLABLE_EXTENSIONS: readonly string[] = ["apk", "apks", "xapk", "apkm", "aab"]

export type DropAction =
  | { kind: "install"; paths: string[] }
  | { kind: "push"; paths: string[]; destination: string }
  | { kind: "ignore"; reason: string }

export interface DropContext {
  /** The feature the drop landed on, when a pane owns the pointer. */
  activeFeature: string | null
  /** The directory the File Explorer is showing, when it is the active tab. */
  explorerDirectory: string | null
  /**
   * Where the drop should go — the device bar's targets, so Run on all
   * installs onto every one of them, as the Install App screen does.
   */
  serials: string[]
}

/**
 * Decide what a drop means.
 *
 * Installables win wherever they land, as they do on the Mac: dropping an APK
 * on the window installs it whatever is on screen, which is the whole appeal.
 * Anything else is a push, and only onto the File Explorer — a file dropped on
 * the logcat has no destination, and inventing one would mean picking a
 * directory on someone else's device.
 */
export function classifyDrop(paths: string[], context: DropContext): DropAction {
  const usable = paths.filter((path) => path.trim() !== "")
  if (usable.length === 0) return { kind: "ignore", reason: "Nothing was dropped." }
  if (context.serials.length === 0) {
    return { kind: "ignore", reason: "Connect a device first." }
  }

  const installables = usable.filter((path) => isInstallable(path))
  if (installables.length > 0) return { kind: "install", paths: installables }

  if (context.activeFeature !== "file-explorer" || context.explorerDirectory === null) {
    return {
      kind: "ignore",
      reason: "Drop an APK or app bundle to install it, or open the File Explorer to push a file.",
    }
  }
  return { kind: "push", paths: usable, destination: context.explorerDirectory }
}

/** Whether a path names one of the installable Android package formats. */
export function isInstallable(path: string): boolean {
  return INSTALLABLE_EXTENSIONS.includes(extensionOf(path))
}

/**
 * The extension, lowercased and without the dot.
 *
 * Both separators, because the path comes from the *host*: a Windows drop
 * carries backslashes, and splitting on `/` alone would read the whole path as
 * one name and find no extension in it.
 */
export function extensionOf(path: string): string {
  const name = path.split(/[/\\]/u).pop() ?? ""
  const dot = name.lastIndexOf(".")
  return dot <= 0 ? "" : name.slice(dot + 1).toLowerCase()
}

/** The last path component, for a message naming what was dropped. */
export function fileName(path: string): string {
  return path.split(/[/\\]/u).pop() ?? path
}

/** "3 files" / "app.apk" — what a result says it acted on. */
export function droppedLabel(paths: string[]): string {
  if (paths.length === 1) return fileName(paths[0] ?? "")
  return `${String(paths.length)} files`
}
