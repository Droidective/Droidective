import { describe, expect, it } from "vitest"

import { readableList, setupRows, shortPermission } from "@/lib/phone-setup"
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

  it("asks for the app first, and does not count permissions without it", () => {
    const rows = setupRows(
      status({ appInstalled: false, appVersion: null, grantedPermissions: [], missingPermissions: BOTH }),
      false,
    )
    expect(rows[0]).toEqual({
      title: "App installed",
      kind: "todo",
      detail: "Install Droidective for Android on the phone first.",
    })
    expect(rows[1]?.kind).toBe("unavailable")
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
