/**
 * What each managed tool is, in words.
 *
 * The daemon serves ids and versions; what a tool is *for* is presentation, so
 * it lives here — the arrangement `icons.ts` and `sidebar.ts` already use, with
 * the same guard: a test fails if the daemon offers an id this table has never
 * heard of, so a tool added to the catalogue cannot appear as a bare slug.
 */

export interface ManagedToolEntry {
  id: string
  installed: boolean
  version: string | null
  pinnedVersion: string
  sizeBytes: number
}

export interface ToolDescription {
  name: string
  purpose: string
}

export const TOOL_DESCRIPTIONS: Readonly<Record<string, ToolDescription>> = {
  jadx: { name: "jadx", purpose: "Decompiles an APK to readable Java." },
  apktool: { name: "Apktool", purpose: "Decodes and rebuilds an APK's resources." },
  "uber-apk-signer": { name: "uber-apk-signer", purpose: "Signs and zipaligns an APK." },
  bundletool: { name: "bundletool", purpose: "Turns an .aab into installable APKs." },
  "temurin-jre": {
    name: "Java runtime",
    purpose: "Runs the tools written in Java, when this machine has no JDK.",
  },
  "frida-server": { name: "frida-server", purpose: "The Frida agent pushed to the device." },
  "frida-gadget": { name: "frida-gadget", purpose: "The Frida library injected into an app." },
  ffmpeg: {
    name: "ffmpeg",
    purpose: "Muxes screen recordings. The Mac bundles one; here it is a download.",
  },
}

/** The name to show, falling back to the id rather than to nothing. */
export function toolName(id: string): string {
  return TOOL_DESCRIPTIONS[id]?.name ?? id
}

export function toolPurpose(id: string): string {
  return TOOL_DESCRIPTIONS[id]?.purpose ?? ""
}

/**
 * What the row's button should offer.
 *
 * Three states, not two: an installed tool whose pin has moved is neither
 * "install" nor "nothing to do", and offering Remove alone would hide the
 * upgrade an app update shipped.
 */
export type ToolAction = "install" | "upgrade" | "installed"

export function toolAction(entry: ManagedToolEntry): ToolAction {
  if (!entry.installed) return "install"
  if (entry.version !== null && entry.version !== entry.pinnedVersion) return "upgrade"
  return "installed"
}

/** `12.4 MB` — a tool's footprint on disk. */
export function toolSizeLabel(bytes: number): string {
  if (bytes <= 0) return "—"
  if (bytes < 1024) return `${String(bytes)} B`
  if (bytes < 1_048_576) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1_048_576).toFixed(1)} MB`
}

/**
 * The version line under a tool's name.
 *
 * An installed tool shows what is on disk, and names the newer pin beside it
 * when there is one — the two together are what makes Upgrade meaningful.
 */
export function toolVersionLabel(entry: ManagedToolEntry): string {
  if (!entry.installed) return `Not installed · ${entry.pinnedVersion} available`
  if (entry.version === null) return "Installed"
  return entry.version === entry.pinnedVersion
    ? entry.version
    : `${entry.version} · ${entry.pinnedVersion} available`
}
