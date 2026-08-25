/**
 * What a custom command's editor is holding, and what it means.
 *
 * Pure, and away from the pane, because these are the rules that decide whether
 * a command runs at all: which runner the line goes through, whether it needs
 * an app picked first, and whether it is complete enough to save. The Mac's
 * `CustomCommandService.draftParts` makes the same call on the same input.
 */

import type { CommandPreset, CustomCommand } from "@/lib/wire"

/**
 * Swift's `.newlines`, character for character.
 *
 * Not just `\n`: the Mac's note is that "\r\n" is one Swift Character, so a
 * `contains("\n")` check misses a pasted CRLF draft and misroutes it as a
 * single adb argv line. Matching the whole set is what keeps the two agreeing.
 */
// oxlint-disable-next-line no-control-regex
const NEWLINE = /[\n\r\u000B\u000C\u0085\u2028\u2029]/u

/** The editor's fields — a command being written, before it is one. */
export interface Draft {
  id: string | null
  name: string
  command: string
  runsInTerminal: boolean
  terminal: string
  pinned: boolean
}

export function emptyDraft(): Draft {
  return { id: null, name: "", command: "", runsInTerminal: false, terminal: "droidective", pinned: false }
}

export function draftOf(command: CustomCommand): Draft {
  return {
    id: command.id,
    name: command.name,
    command: command.command,
    runsInTerminal: command.runsInTerminal,
    terminal: command.terminal,
    pinned: command.pinned,
  }
}

export function draftFromPreset(preset: CommandPreset): Draft {
  return { ...emptyDraft(), name: preset.name, command: preset.command }
}

/**
 * Which runner a typed line goes through.
 *
 * A leading `adb` token means the adb runner and is stripped, exactly as the
 * Mac's `draftParts` does — someone typing the command they would paste into a
 * terminal should not have to know the difference. Anything else, multi-line
 * included, is a shell line.
 */
export function inferKind(line: string): { kind: "adb" | "shell"; command: string } {
  const trimmed = line.trim()
  // Any newline at all forces shell, CR included. The Mac's note here is worth
  // keeping: "\r\n" is one Swift Character, so a `contains("\n")` check misses
  // a pasted CRLF draft and misroutes it as a single adb argv line.
  if (NEWLINE.test(trimmed)) return { kind: "shell", command: trimmed }
  // The exact `adb` token only — `adbx`, `ADB` and a tab separator are all
  // shell lines, and the login shell resolves them, right or wrong.
  if (trimmed !== "adb" && !trimmed.startsWith("adb ")) {
    return { kind: "shell", command: trimmed }
  }
  // A bare "adb" is adb-kind with nothing to run; the editor rejects it.
  return { kind: "adb", command: trimmed.slice("adb".length).trim() }
}

/**
 * Whether the command names an app.
 *
 * `{bundleId}` is what makes a command need one picked before it can run, so
 * this is derived rather than a checkbox: a template and a flag that disagreed
 * would run against nothing and say nothing about why.
 */
export function needsBundle(command: string): boolean {
  return command.includes("{bundleId}")
}

/** Whether a draft is complete enough to save. */
export function isComplete(draft: Draft): boolean {
  return draft.name.trim() !== "" && draft.command.trim() !== ""
}

/**
 * The draft as a stored command, keeping the created stamp of the one it is
 * replacing.
 *
 * `now` is passed rather than read, so a test does not depend on the clock —
 * and so an edit cannot restamp a command someone saved months ago.
 */
export function toCommand(draft: Draft, now: number, existing: CustomCommand | null): CustomCommand {
  const { kind, command } = inferKind(draft.command)
  return {
    id: draft.id ?? `${now}-${Math.round(now % 1_000_000)}`,
    name: draft.name.trim(),
    command,
    kind,
    needsBundle: needsBundle(command),
    runsInTerminal: draft.runsInTerminal,
    terminal: draft.terminal,
    pinned: draft.pinned,
    createdAt: existing?.createdAt ?? now / 1000,
  }
}

/** The list with `command` added or replaced, keeping the existing order. */
export function upserted(commands: CustomCommand[], command: CustomCommand): CustomCommand[] {
  const at = commands.findIndex((existing) => existing.id === command.id)
  if (at === -1) return [...commands, command]
  return commands.map((existing, index) => (index === at ? command : existing))
}

export function removed(commands: CustomCommand[], id: string): CustomCommand[] {
  return commands.filter((command) => command.id !== id)
}
