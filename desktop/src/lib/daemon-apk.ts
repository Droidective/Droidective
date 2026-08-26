/**
 * The APK tool calls: inspect, sign, and convert a bundle.
 *
 * Their own module rather than more of `daemon-settings.ts`, which is at the
 * line budget that made it a separate file. Re-exported from `@/lib/daemon`.
 */

import { invoke } from "@tauri-apps/api/core"
import type {
  AabConvertResponse,
  ApkKeystore,
  ApkReport,
  ApkSignResponse,
  ApkToolchain,
  DecompileFileText,
  DecompileHits,
  DecompileMode,
  DecompileRebuildResponse,
  DecompileTree,
  InstallResponse,
} from "@/lib/wire"

/** Which of the APK tools are on this machine. */
export function apkToolchain(): Promise<ApkToolchain> {
  return invoke("apk_toolchain")
}

/**
 * Reads what it can from an APK.
 *
 * Best-effort by construction: without aapt2 it still answers a name and a
 * size, with `hasDetails` false.
 */
export function inspectApk(path: string): Promise<ApkReport> {
  return invoke("inspect_apk", { path })
}

/** Zipaligns and signs an APK with a keystore. */
export function signApk(
  input: string,
  output: string,
  keystore: ApkKeystore,
): Promise<ApkSignResponse> {
  return invoke("sign_apk", { input, output, keystore })
}

/**
 * Builds a universal APK from an Android App Bundle.
 *
 * No keystore leaves bundletool's own debug key, which is what the Mac's
 * screen does until someone chooses one.
 */
export function convertAab(
  input: string,
  outputDirectory: string,
  keystore: ApkKeystore | null,
): Promise<AabConvertResponse> {
  return invoke("convert_aab", { input, outputDirectory, keystore })
}

/**
 * Picks one file, answering its path — or null when the dialog was dismissed,
 * which is a choice rather than a failure.
 *
 * The picker runs in Rust, not here: a webview drag hands over a `File` with no
 * path, and every one of these tools needs a real one.
 */
export function pickFile(label: string, extensions: string[]): Promise<string | null> {
  return invoke("pick_file", { label, extensions })
}

/** Picks a folder — where a signed APK or a converted bundle should land. */
export function pickFolder(): Promise<string | null> {
  return invoke("pick_folder")
}

/**
 * Installs a package this app already knows the path of.
 *
 * Separate from `pickAndInstall`: a converted bundle has a path already, and a
 * dialog would ask someone to find the file the app just made.
 */
export function installPath(serials: string[], path: string): Promise<InstallResponse> {
  return invoke("install_path", { serials, path })
}

/**
 * Runs jadx or apktool over one APK and answers the tree it wrote.
 *
 * A previous run of the same APK and mode is reused unless `refresh` — the
 * output is deterministic and jadx is slow enough that re-running it on every
 * revisit is the difference between a screen and a wait.
 */
export function decompileApk(
  path: string,
  mode: DecompileMode,
  refresh = false,
): Promise<DecompileTree> {
  return invoke("decompile_apk", { path, mode, refresh })
}

/** One decompiled file's text. `root` is what the daemon confines the read to. */
export function decompiledFile(root: string, path: string): Promise<DecompileFileText> {
  return invoke("decompiled_file", { root, path })
}

/** Case-insensitive search across one decompile's output. */
export function searchDecompiled(root: string, query: string): Promise<DecompileHits> {
  return invoke("search_decompiled", { root, query })
}

/** Rebuilds an apktool source tree back into an APK. */
export function rebuildDecompiled(
  root: string,
  sourceDir: string,
  output: string,
): Promise<DecompileRebuildResponse> {
  return invoke("rebuild_decompiled", { root, sourceDir, output })
}
