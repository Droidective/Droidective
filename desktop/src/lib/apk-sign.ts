/**
 * Naming the file a signing or conversion produces.
 *
 * Pure and here rather than inline, because getting it wrong overwrites the
 * input: an output that lands on the same path as the APK being read destroys
 * the unsigned original, and there is no undo for that.
 */

/** `app.apk` → `app-signed.apk`. Keeps the extension, never the same name. */
export function signedApkName(inputPath: string): string {
  const file = baseName(inputPath)
  const dot = file.lastIndexOf(".")
  if (dot <= 0) return `${file}-signed.apk`
  return `${file.slice(0, dot)}-signed${file.slice(dot)}`
}

/** `app.aab` → `app-universal.apk` — a bundle becomes an APK, so the name says so. */
export function convertedApkName(inputPath: string): string {
  const file = baseName(inputPath)
  const dot = file.lastIndexOf(".")
  return `${dot <= 0 ? file : file.slice(0, dot)}-universal.apk`
}

/** The last path component, for either separator — the app ships on Windows. */
export function baseName(path: string): string {
  const at = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"))
  return at === -1 ? path : path.slice(at + 1)
}
