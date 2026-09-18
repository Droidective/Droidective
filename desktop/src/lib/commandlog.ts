import type { CommandLogEntry } from "@/lib/wire"

/**
 * The Command Log's rendering decisions, ported from the Mac's
 * `CommandLogRow` — so a row reads the same in both apps.
 */

/**
 * The trailing status on a collapsed row: `exit 0 · 12ms`.
 *
 * A process that was killed rather than exiting has no code, and the Mac says
 * so in the word rather than substituting a number — a timed-out adb call that
 * read "exit 0" would be a lie about what happened.
 */
export function exitLabel(entry: CommandLogEntry): string {
  const code = entry.exitCode === null ? "killed" : String(entry.exitCode)
  return `exit ${code} · ${entry.durationMs}ms`
}

/** Whether the row's status reads as success — the accent/red split. */
export function succeeded(entry: CommandLogEntry): boolean {
  return entry.exitCode === 0
}

/**
 * The row's time, in the reader's locale.
 *
 * `Text(entry.timestamp, style: .time)` is a short local time on the Mac, so
 * this asks for the same thing rather than picking a format of its own.
 */
export function timeLabel(at: number, locale?: string): string {
  return new Date(at).toLocaleTimeString(locale, { hour: "numeric", minute: "2-digit", second: "2-digit" })
}

/**
 * Whether an expanded row has anything to show.
 *
 * The Mac prints "(no output)" rather than an empty block, because a command
 * that printed nothing and a command whose output was lost look identical
 * otherwise.
 */
export function hasOutput(entry: CommandLogEntry): boolean {
  return entry.stdout.length > 0 || entry.stderr.length > 0
}

/**
 * One entry as text, for a bug report.
 *
 * Not on the Mac — its sheet has no copy button — so this is the *shape* a
 * copy takes here and nothing about it is a divergence in behaviour someone
 * has to relearn: the sheet still shows exactly what the Mac's shows.
 */
export function entryAsText(entry: CommandLogEntry, locale?: string): string {
  const lines = [`${timeLabel(entry.at, locale)}  ${entry.command}`, exitLabel(entry)]
  if (entry.stdout.length > 0) lines.push("", entry.stdout.trimEnd())
  if (entry.stderr.length > 0) lines.push("", entry.stderr.trimEnd())
  return lines.join("\n")
}

/** Every entry as text, newest first — the order the sheet shows them in. */
export function logAsText(entries: readonly CommandLogEntry[], locale?: string): string {
  return entries.map((entry) => entryAsText(entry, locale)).join("\n\n")
}
