/**
 * The wire shapes for the APK tools.
 *
 * Their own module because three features share them — inspect, sign, and the
 * bundle converter — and what they have in common is the part that fails: a
 * missing SDK build-tool rather than anything about the file.
 */

/**
 * Which of the tools this machine has.
 *
 * Asked before a file is picked: the SDK build-tools are detected rather than
 * downloadable, so "install the build-tools" is advice a screen can give up
 * front. After a failed run it reads as though the APK was the problem.
 */
export interface ApkToolchain {
  aapt2: boolean
  apksigner: boolean
  zipalign: boolean
  java: boolean
  bundletool: boolean
}

export interface ApkSigner {
  subjectDN: string | null
  sha256: string | null
  sha1: string | null
}

export interface ApkReport {
  fileName: string
  fileSizeBytes: number
  label: string | null
  packageName: string | null
  versionName: string | null
  versionCode: string | null
  minSdk: string | null
  targetSdk: string | null
  /**
   * False when aapt2 was missing. The name and the size are still real — this
   * is how the screen says why that is all it has.
   */
  hasDetails: boolean
  permissions: string[]
  features: string[]
  isDebuggable: boolean
  signatureSchemes: string[]
  signers: ApkSigner[]
}

/**
 * A keystore, as the client hands one over.
 *
 * The password crosses the loopback socket in the body, which is the trust
 * boundary the token already establishes. It never reaches a command line —
 * the daemon writes it to a 0600 temp file for exactly that reason.
 */
export interface ApkKeystore {
  path: string
  storePassword: string
  keyAlias: string | null
  keyPassword: string | null
}

export interface ApkSignResponse {
  ok: boolean
  message: string
  output: string | null
}

export interface AabConvertResponse {
  path: string
  sizeBytes: number
}

/** Which decompiler ran. Mirrors the daemon's own enum. */
export type DecompileMode = "jadx" | "apktool"

/**
 * One entry in a decompiled tree.
 *
 * `children` absent means a file and present — even empty — means a directory,
 * which is what puts a disclosure triangle on the right rows. An empty
 * directory is still a directory.
 */
export interface DecompileNode {
  name: string
  path: string
  children?: DecompileNode[]
}

export interface DecompileTree {
  /**
   * The output directory. Handed back on every read and search so the daemon
   * can confine them to it — a path from this client is otherwise a read of
   * any file the developer can read.
   */
  root: string
  tree: DecompileNode
}

export interface DecompileFileText {
  text: string
  /** True when the file was longer than the daemon will send in one piece. */
  truncated: boolean
  byteCount: number
}

export interface DecompileHit {
  path: string
  line: number
  text: string
}

export interface DecompileHits {
  hits: DecompileHit[]
  /** True when the cap was reached, so the list is partial rather than whole. */
  capped: boolean
}

export interface DecompileRebuildResponse {
  output: string
}
