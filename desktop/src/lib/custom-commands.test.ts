/**
 * The editor's rules, against the vectors ADBKit's `CustomCommandTests` asserts
 * for `draftParts`.
 *
 * The same inputs on purpose. Which runner a line goes through decides whether
 * it is tokenized into argv or handed to a login shell, so a port that
 * classified one differently would run someone's command a different way with
 * nothing failing.
 */

import { describe, expect, it } from "vitest"

import {
  draftFromPreset,
  emptyDraft,
  inferKind,
  isComplete,
  needsBundle,
  removed,
  toCommand,
  upserted,
} from "@/lib/custom-commands"
import type { CustomCommand } from "@/lib/wire"

describe("which runner a line goes through", () => {
  it("routes a leading adb token to the adb runner and strips it", () => {
    expect(inferKind("adb shell am force-stop {bundleId}")).toEqual({
      kind: "adb",
      command: "shell am force-stop {bundleId}",
    })
    expect(inferKind("  adb devices  ")).toEqual({ kind: "adb", command: "devices" })
  })

  it("treats a bare adb as adb-kind with nothing to run", () => {
    // The editor rejects it for being incomplete, not for being shell.
    expect(inferKind("adb")).toEqual({ kind: "adb", command: "" })
  })

  it("routes everything else to the shell", () => {
    expect(inferKind("~/scripts/reset.sh {serial}")).toEqual({
      kind: "shell",
      command: "~/scripts/reset.sh {serial}",
    })
    // Only the exact `adb ` token — a longer word or a different case is a
    // shell command, and the login shell resolves it, right or wrong.
    expect(inferKind("adbx devices")).toEqual({ kind: "shell", command: "adbx devices" })
    expect(inferKind("ADB devices")).toEqual({ kind: "shell", command: "ADB devices" })
    // Pinned: a tab separator is not the "adb " prefix.
    expect(inferKind("adb\tdevices")).toEqual({ kind: "shell", command: "adb\tdevices" })
    expect(inferKind("   ")).toEqual({ kind: "shell", command: "" })
  })

  it("forces multi-line to the shell, CRLF included", () => {
    expect(inferKind("adb devices\necho done").kind).toBe("shell")
    // The trap the Mac names: "\r\n" is one Swift Character, so a `\n`-only
    // check misses a pasted CRLF draft and misroutes it as one adb argv line.
    expect(inferKind("adb devices\r\necho done").kind).toBe("shell")
    expect(inferKind("adb devices\recho done").kind).toBe("shell")
  })

  it("does not mistake an ordinary multi-word command for a multi-line one", () => {
    // A space is not a newline. Getting this wrong would send every real adb
    // command through the login shell instead of argv.
    expect(inferKind("adb shell pm list packages -3").kind).toBe("adb")
  })
})

describe("whether a command names an app", () => {
  it("is derived from the template rather than declared", () => {
    // A template and a flag that disagreed would run against nothing and say
    // nothing about why.
    expect(needsBundle("shell am force-stop {bundleId}")).toBe(true)
    expect(needsBundle("shell pm list packages -3")).toBe(false)
  })
})

describe("saving a draft", () => {
  const existing: CustomCommand = {
    id: "kept",
    name: "Old name",
    command: "devices",
    kind: "adb",
    needsBundle: false,
    runsInTerminal: false,
    terminal: "droidective",
    pinned: false,
    createdAt: 1_000,
  }

  it("needs both a name and a command", () => {
    expect(isComplete(emptyDraft())).toBe(false)
    expect(isComplete({ ...emptyDraft(), name: "Only a name" })).toBe(false)
    expect(isComplete({ ...emptyDraft(), name: "n", command: "adb devices" })).toBe(true)
  })

  it("keeps the created stamp of the command it replaces", () => {
    // An edit must not restamp something saved months ago.
    const draft = { ...emptyDraft(), id: "kept", name: "New name", command: "adb devices" }
    expect(toCommand(draft, 9_999_000, existing).createdAt).toBe(1_000)
  })

  it("stamps a new command from the clock it was given", () => {
    const draft = { ...emptyDraft(), name: "New", command: "adb devices" }
    expect(toCommand(draft, 2_000_000, null).createdAt).toBe(2_000)
  })

  it("records the inferred kind and bundle need, not the typed line", () => {
    const draft = { ...emptyDraft(), name: "Stop", command: "adb shell am force-stop {bundleId}" }
    const command = toCommand(draft, 1, null)
    expect(command.kind).toBe("adb")
    expect(command.command).toBe("shell am force-stop {bundleId}")
    expect(command.needsBundle).toBe(true)
  })

  it("trims the name", () => {
    expect(toCommand({ ...emptyDraft(), name: "  Spaced  ", command: "adb devices" }, 1, null).name)
      .toBe("Spaced")
  })

  it("starts a draft from a preset with its template intact", () => {
    const draft = draftFromPreset({
      name: "Force-stop app",
      command: "shell am force-stop {bundleId}",
      needsBundle: true,
      detail: "…",
    })
    expect(draft.name).toBe("Force-stop app")
    expect(draft.id).toBeNull()
    expect(toCommand(draft, 1, null).needsBundle).toBe(true)
  })
})

describe("the list transforms the three verbs are", () => {
  const one: CustomCommand = {
    id: "1",
    name: "One",
    command: "devices",
    kind: "adb",
    needsBundle: false,
    runsInTerminal: false,
    terminal: "droidective",
    pinned: false,
    createdAt: 1,
  }
  const two = { ...one, id: "2", name: "Two" }

  it("appends a command it has not seen", () => {
    expect(upserted([one], two).map((command) => command.id)).toEqual(["1", "2"])
  })

  it("replaces in place, keeping the order", () => {
    // An edit that moved a row to the end would reorder someone's list for
    // them every time they fixed a typo.
    const edited = { ...one, name: "Renamed" }
    const result = upserted([one, two], edited)
    expect(result.map((command) => command.id)).toEqual(["1", "2"])
    expect(result[0]?.name).toBe("Renamed")
  })

  it("removes by id", () => {
    expect(removed([one, two], "1").map((command) => command.id)).toEqual(["2"])
    expect(removed([one], "absent")).toHaveLength(1)
  })
})
