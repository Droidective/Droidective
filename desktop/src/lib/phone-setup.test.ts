import { describe, expect, it } from "vitest"

import {
  actionTitle,
  readableList,
  setupRows,
  shortPermission,
  streamedStatus,
} from "@/lib/phone-setup"
import type { PhoneSetupStatus } from "@/lib/wire"

const BOTH = ["android.permission.WRITE_SECURE_SETTINGS", "android.permission.DUMP"]

function status(over: Partial<PhoneSetupStatus> = {}): PhoneSetupStatus {
  return {
    appInstalled: true,
    appVersion: "0.1.0",
    grantedPermissions: BOTH,
    missingPermissions: [],
    shizukuInstalled: true,
    shizukuRunning: true,
    needsSetup: false,
    sdk: 36,
    latestVersion: "0.1.0",
    latestProblem: null,
    step: "none",
    hasWork: false,
    offer: null,
    ...over,
  }
}

describe("setupRows", () => {
  it("reads every row as done on a set-up phone, with the Mac's words", () => {
    expect(setupRows(status(), false)).toEqual([
      { title: "App installed", kind: "done", detail: "Droidective for Android 0.1.0" },
      { title: "Permissions granted", kind: "done", detail: "WRITE_SECURE_SETTINGS and DUMP" },
      { title: "Shizuku running", kind: "done", detail: "Running" },
    ])
  })

  it("names what is missing rather than saying something is", () => {
    const rows = setupRows(
      status({
        grantedPermissions: [BOTH[1] ?? ""],
        missingPermissions: [BOTH[0] ?? ""],
        shizukuRunning: false,
        needsSetup: true,
      }),
      false,
    )
    expect(rows[1]).toEqual({
      title: "Permissions granted",
      kind: "todo",
      detail: "Missing WRITE_SECURE_SETTINGS.",
    })
    expect(rows[2]).toEqual({
      title: "Shizuku running",
      kind: "todo",
      detail: "Installed, not running.",
    })
  })

  it("treats a missing Shizuku as optional, not as a step left undone", () => {
    const shizuku = setupRows(status({ shizukuInstalled: false, shizukuRunning: false }), false)[2]
    expect(shizuku?.kind).toBe("unavailable")
    expect(shizuku?.detail).toMatch(/Optional/u)
  })

  it("says an install downloads the latest release, and counts no permissions without the app", () => {
    const rows = setupRows(
      status({
        appInstalled: false,
        appVersion: null,
        grantedPermissions: [],
        missingPermissions: BOTH,
        latestVersion: "0.1.1",
        step: "install",
        hasWork: true,
      }),
      false,
    )
    expect(rows[0]).toEqual({
      title: "App installed",
      kind: "todo",
      detail: "Not installed. Install downloads 0.1.1 from GitHub.",
    })
    expect(rows[1]?.kind).toBe("unavailable")
  })

  it("says what an update replaces", () => {
    const row = setupRows(status({ latestVersion: "0.1.1", step: "update", hasWork: true }), false)[0]
    expect(row).toEqual({
      title: "App installed",
      kind: "todo",
      detail: "0.1.0 is installed. Update installs 0.1.1.",
    })
  })

  it("names why a phone without the app can't be given it", () => {
    const absent = { appInstalled: false, appVersion: null, step: "none" as const }
    expect(setupRows(status({ ...absent, sdk: 29 }), false)[0]).toEqual({
      title: "App installed",
      kind: "unavailable",
      detail: "Not installed. Droidective for Android needs Android 11 or later.",
    })
    expect(
      setupRows(status({ ...absent, latestVersion: null, latestProblem: "offline" }), false)[0],
    ).toEqual({
      title: "App installed",
      kind: "unavailable",
      detail: "Not installed, and the latest release couldn't be found: offline",
    })
  })

  it("leaves the version off when the phone did not report one", () => {
    expect(setupRows(status({ appVersion: null }), false)[0]?.detail).toBe("Droidective for Android")
  })

  it("is checking before the first answer, and unreadable after a failed one", () => {
    expect(setupRows(null, true).map((row) => row.kind)).toEqual(["checking", "checking", "checking"])
    // A failed read is not a phone with nothing installed.
    const failed = setupRows(null, false)
    expect(failed.map((row) => row.kind)).toEqual(["unavailable", "unavailable", "unavailable"])
    expect(failed[0]?.detail).toBe("Couldn't read the phone.")
  })
})

describe("actionTitle", () => {
  it("is the verb the run starts with", () => {
    expect(actionTitle(status({ step: "install" }))).toBe("Install")
    expect(actionTitle(status({ step: "update" }))).toBe("Update")
    expect(actionTitle(status())).toBe("Set Up")
    expect(actionTitle(null)).toBe("Set Up")
  })
})

describe("streamedStatus", () => {
  it("fills in the keys Swift leaves out, so a streamed status reads like a route's", () => {
    // What arrives on the stream for a phone with no version, no SDK and no
    // answer from GitHub: only the fields that always have a value.
    const read = streamedStatus({
      appInstalled: true,
      grantedPermissions: BOTH,
      missingPermissions: [],
      shizukuInstalled: false,
      shizukuRunning: false,
      needsSetup: false,
      step: "none",
      hasWork: false,
    })
    expect(read.appVersion).toBeNull()
    expect(read.sdk).toBeNull()
    expect(read.latestVersion).toBeNull()
    expect(read.offer).toBeNull()
    expect(setupRows(read, false)[0]?.detail).toBe("Droidective for Android")
  })

  it("keeps an offer, with its versions filled in", () => {
    const read = streamedStatus({
      appInstalled: true,
      offer: { kind: "setUp", menuTitle: "Set Up Droidective on This Phone…" },
    })
    expect(read.offer).toEqual({
      kind: "setUp",
      menuTitle: "Set Up Droidective on This Phone…",
      from: null,
      to: null,
    })
  })
})

describe("shortPermission", () => {
  it("keeps the constant's own name", () => {
    expect(shortPermission("android.permission.DUMP")).toBe("DUMP")
    expect(shortPermission("DUMP")).toBe("DUMP")
  })
})

describe("readableList", () => {
  it("reads like the Mac's list of permission names", () => {
    expect(readableList([])).toBe("")
    expect(readableList(["DUMP"])).toBe("DUMP")
    expect(readableList(["A", "B"])).toBe("A and B")
    expect(readableList(["WRITE_SECURE_SETTINGS", "DUMP", "READ_DROPBOX_DATA"])).toBe(
      "WRITE_SECURE_SETTINGS, DUMP and READ_DROPBOX_DATA",
    )
  })
})
