/**
 * What APK Decompile *does*, away from React.
 *
 * Split out of `useDecompile` because none of it is a hook — it is the daemon
 * calls and the small decisions around them, and keeping it here lets the hook
 * stay about state.
 */

import {
  asDaemonError,
  decompileApk,
  decompiledFile,
  installTool,
  pickFile,
  pickFolder,
  rebuildDecompiled,
  searchDecompiled,
} from "@/lib/daemon"
import { ancestors, defaultExpanded } from "@/lib/decompile"
import type { ToastInput } from "@/lib/notifications"
import type { DecompileFileText, DecompileHits, DecompileMode, DecompileTree } from "@/lib/wire"

export type Show = (input: ToastInput) => void

/**
 * A failure as one line.
 *
 * Toasts carry no separate detail field, and the daemon's detail is the half
 * that says *why* — apktool's own words rather than "the tool could not
 * finish", which on its own sends nobody anywhere.
 */
export function withDetail(error: { message: string; detail?: string | null }): string {
  const detail = error.detail
  if (detail === null || detail === undefined || detail === "") return error.message
  return `${error.message} ${detail}`
}

/**
 * Everything APK Decompile does, away from the markup.
 *
 * Its own hook because the pane is two screens over one piece of state — a
 * chooser and a browser — and threading eleven values plus their setters
 * between them is what makes a component too big to read.
 */
export async function runDecompile(
  path: string,
  mode: DecompileMode,
  refresh: boolean,
  sink: {
    setTree: (tree: DecompileTree | null) => void
    setExpanded: (expanded: ReadonlySet<string>) => void
    show: Show
  },
): Promise<void> {
  try {
    const answer = await decompileApk(path, mode, refresh)
    sink.setTree(answer)
    sink.setExpanded(defaultExpanded(answer.tree))
  } catch (thrown) {
    sink.setTree(null)
    sink.show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

/** Download one decompiler, saying which when it lands or when it does not. */
export async function fetchTool(mode: DecompileMode, show: Show): Promise<void> {
  try {
    await installTool(mode)
    show({ message: `${mode} is ready.`, ok: true })
  } catch (thrown) {
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

/** Pick an APK, then decompile it. A dismissed dialog is a choice, not a failure. */
export async function chooseApk(
  mode: DecompileMode,
  setPath: (path: string) => void,
  start: (path: string, mode: DecompileMode, refresh: boolean) => void,
  show: Show,
): Promise<void> {
  try {
    const picked = await pickFile("APK", ["apk"])
    if (picked === null) return
    setPath(picked)
    start(picked, mode, false)
  } catch (thrown) {
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

export async function readFile(
  root: string,
  path: string,
  setSource: (source: DecompileFileText | null) => void,
  show: Show,
): Promise<void> {
  try {
    setSource(await decompiledFile(root, path))
  } catch (thrown) {
    setSource(null)
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

export async function runSearch(
  root: string,
  query: string,
  setHits: (hits: DecompileHits) => void,
  show: Show,
): Promise<void> {
  try {
    setHits(await searchDecompiled(root, query))
  } catch (thrown) {
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

export async function runRebuild(root: string, path: string | null, show: Show): Promise<void> {
  try {
    const folder = await pickFolder()
    if (folder === null) return
    const base = (path ?? "app").split("/").pop() ?? "app"
    const name = base.replace(/\.apk$/iu, "")
    const answer = await rebuildDecompiled(root, root, `${folder}/${name}-rebuilt.apk`)
    // Unsigned by design: apktool's output will not install until it is signed,
    // and APK Sign is the screen that does that.
    show({ message: "Rebuilt. Sign it before installing.", revealPath: answer.output, ok: true })
  } catch (thrown) {
    show({ message: withDetail(asDaemonError(thrown)), ok: false })
  }
}

/** Opening the tree down to a file, so revealing a hit does not leave it hidden. */
export function withAncestors(
  expanded: ReadonlySet<string>,
  root: string,
  path: string,
): Set<string> {
  const next = new Set(expanded)
  for (const directory of ancestors(root, path)) next.add(directory)
  return next
}
