/**
 * Everything the File Explorer decides, away from the pane that renders it.
 *
 * This is the first screen in this app that *writes* to a device, so the rules
 * that matter — which paths an operation targets, what a batch reports when
 * one item fails, what a right-click acts on — are here where they can be
 * tested, rather than inside a component where they can only be clicked.
 *
 * Nothing in this file quotes anything. Device-shell quoting happens exactly
 * once, in ADBKit's `FileExplorerService`; a path escaped on the way out would
 * arrive to be quoted a second time and address the wrong file.
 */

import type { FileEntry } from "@/lib/wire"

/** Shared storage, where the Mac's explorer opens. */
export const SDCARD_ROOT = "/sdcard"

/**
 * Where the browser currently is.
 *
 * Root mode browses the whole filesystem from `/`; otherwise everything hangs
 * off `/sdcard`, which is all adb can read without `su`.
 */
export function currentPath(components: readonly string[], rootMode: boolean): string {
  if (rootMode) return `/${components.join("/")}`
  return components.length === 0 ? SDCARD_ROOT : `${SDCARD_ROOT}/${components.join("/")}`
}

/** A child of the directory currently open. */
export function childPath(directory: string, name: string): string {
  return directory === "/" ? `/${name}` : `${directory}/${name}`
}

/** The last component of a device path — what a pulled file gets called. */
export function leafName(path: string): string {
  const parts = path.split("/").filter((part) => part !== "")
  return parts.at(-1) ?? path
}

export interface Crumb {
  label: string
  /** How many components to keep when this crumb is clicked. */
  depth: number
}

/** The clickable path, leading with the root the browser is anchored to. */
export function breadcrumbs(components: readonly string[], rootMode: boolean): Crumb[] {
  const root: Crumb = { label: rootMode ? "/" : "sdcard", depth: 0 }
  return [root, ...components.map((label, index) => ({ label, depth: index + 1 }))]
}

/**
 * The device-side clipboard: what Copy or Cut remembered.
 *
 * Device paths, not entries — the folder they came from may well be closed by
 * the time they are pasted.
 */
export interface FileClipboard {
  paths: string[]
  isCut: boolean
}

/** What the Paste button says. */
export function pasteLabel(clipboard: FileClipboard): string {
  return clipboard.paths.length === 1
    ? `Paste ${leafName(clipboard.paths[0] ?? "")}`
    : `Paste ${String(clipboard.paths.length)} items`
}

/** The daemon's verb for a paste — `move` after a Cut, `copy` after a Copy. */
export function pasteOperation(clipboard: FileClipboard): "move" | "copy" {
  return clipboard.isCut ? "move" : "copy"
}

/** "3 items" / "note.txt" — how a batch names itself in a message. */
export function batchLabel(names: readonly string[]): string {
  return names.length === 1 ? (names[0] ?? "") : `${String(names.length)} items`
}

/**
 * What a right-click acts on.
 *
 * Inside a multi-selection it is the whole selection; anywhere else it is the
 * one row, selected or not. The Mac's `targets(for:)` rule — right-clicking one
 * checked row out of five and getting only that row would be a nasty surprise
 * for Delete.
 */
export function targetsFor(
  entry: FileEntry,
  selection: ReadonlySet<string>,
  entries: readonly FileEntry[],
): FileEntry[] {
  if (selection.has(entry.name) && selection.size > 1) {
    return entries.filter((candidate) => selection.has(candidate.name))
  }
  return [entry]
}

export function toggleSelected(selection: ReadonlySet<string>, name: string): Set<string> {
  const next = new Set(selection)
  if (next.has(name)) next.delete(name)
  else next.add(name)
  return next
}

/** Select All until everything is chosen, then Deselect All. */
export function selectAllToggle(
  selection: ReadonlySet<string>,
  entries: readonly FileEntry[],
): Set<string> {
  if (entries.length > 0 && selection.size === entries.length) return new Set()
  return new Set(entries.map((entry) => entry.name))
}

/**
 * Drops names that are no longer there.
 *
 * A refresh after a delete leaves a selection pointing at rows that have gone,
 * and a stale name in it would put the selection bar's count out by however
 * many were removed.
 */
export function pruneSelection(
  selection: ReadonlySet<string>,
  entries: readonly FileEntry[],
): Set<string> {
  const present = new Set(entries.map((entry) => entry.name))
  return new Set([...selection].filter((name) => present.has(name)))
}

/** The sentence on the delete confirmation. */
export function deletePrompt(targets: readonly FileEntry[]): string {
  return `Delete ${batchLabel(targets.map((entry) => entry.name))}? This can't be undone.`
}

/** A folder name as typed, or null when there is nothing to create. */
export function folderNameToCreate(raw: string): string | null {
  const trimmed = raw.trim()
  return trimmed === "" ? null : trimmed
}

export interface BatchOutcome {
  ok: boolean
  message: string
}

/**
 * Runs calls one at a time, stopping at the first refusal.
 *
 * Serial rather than concurrent, and short-circuiting: deleting five files
 * where the second is not yours should stop at the second, not carry on and
 * report four successes and a failure in no particular order.
 */
export async function runInOrder<Result extends { ok: boolean }>(
  calls: readonly (() => Promise<Result>)[],
): Promise<Result[]> {
  const results: Result[] = []
  for (const call of calls) {
    const result = await call()
    results.push(result)
    if (!result.ok) break
  }
  return results
}

/**
 * What a multi-item operation reports.
 *
 * Stop-on-first-failure, like the Mac's loop: the alternative is a summary that
 * says "3 of 5" and leaves you to work out which three. The caller stops
 * issuing calls at the same point, so `results` is short when something failed.
 */
export function summariseBatch(
  results: readonly { ok: boolean; message: string }[],
  succeeded: string,
): BatchOutcome {
  const failure = results.find((result) => !result.ok)
  if (failure) return { ok: false, message: failure.message }
  return { ok: true, message: succeeded }
}

const UNITS = ["bytes", "KB", "MB", "GB", "TB"] as const

/**
 * A file size, in the decimal units `ByteCountFormatter` uses on the Mac — so
 * the same file reads the same on both.
 */
export function formatBytes(size: number): string {
  if (!Number.isFinite(size) || size <= 0) return "0 bytes"
  if (size < 1000) return `${String(Math.round(size))} bytes`
  let value = size
  let unit = 0
  while (value >= 1000 && unit < UNITS.length - 1) {
    value /= 1000
    unit += 1
  }
  // One decimal below 100, none above — 1.2 MB, then 340 MB.
  const rounded = value < 100 ? Math.round(value * 10) / 10 : Math.round(value)
  return `${String(rounded)} ${UNITS[unit] ?? "bytes"}`
}
