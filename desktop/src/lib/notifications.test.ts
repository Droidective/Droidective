import { describe, expect, it } from "vitest"
import {
  badgeText,
  isImportant,
  NOTIFICATION_LIMIT,
  relativeTime,
  resolveLevel,
  systemNotification,
  systemTitle,
  toNotification,
  toToast,
  withNotification,
  type AppNotification,
} from "@/lib/notifications"

describe("resolveLevel", () => {
  it("derives success and error from ok when no level is given", () => {
    expect(resolveLevel({ message: "m", ok: true })).toBe("success")
    expect(resolveLevel({ message: "m", ok: false })).toBe("error")
  })

  it("lets an explicit level win", () => {
    expect(resolveLevel({ message: "m", ok: true, level: "warning" })).toBe("warning")
  })
})

describe("isImportant", () => {
  it("keeps every error and warning", () => {
    // These are what someone scrolls back to find.
    expect(isImportant({ message: "m", ok: false })).toBe(true)
    expect(isImportant({ message: "m", ok: true, level: "warning" })).toBe(true)
  })

  it("keeps a success that produced a file", () => {
    expect(isImportant({ message: "Saved", ok: true, revealPath: "/tmp/x" })).toBe(true)
  })

  it("drops a routine confirmation", () => {
    // "Copied to the clipboard" is a confirmation, not a record, and a history
    // full of them is a history nobody reads.
    expect(isImportant({ message: "Copied", ok: true })).toBe(false)
    expect(isImportant({ message: "m", ok: true, level: "info" })).toBe(false)
  })

  it("lets the caller override either way", () => {
    expect(isImportant({ message: "m", ok: false, important: false })).toBe(false)
    expect(isImportant({ message: "Copied", ok: true, important: true })).toBe(true)
  })
})

describe("toToast", () => {
  it("carries the extras and the resolved level", () => {
    const toast = toToast(
      { message: "Saved", ok: true, revealPath: "/tmp/x", copyText: "abc" },
      "t1",
    )
    expect(toast).toEqual({
      id: "t1",
      message: "Saved",
      level: "success",
      copyText: "abc",
      revealPath: "/tmp/x",
      important: true,
      notifiesWhenBackgrounded: true,
    })
  })
})

describe("toNotification", () => {
  it("keeps the toast's id, so dismissing one cannot orphan the other", () => {
    const toast = toToast({ message: "Boom", ok: false }, "t7")
    expect(toNotification(toast, 1000)).toEqual({
      id: "t7",
      message: "Boom",
      level: "error",
      copyText: undefined,
      revealPath: undefined,
      at: 1000,
    })
  })
})

const entry = (id: string): AppNotification => ({
  id,
  message: id,
  level: "error",
  copyText: undefined,
  revealPath: undefined,
  at: 0,
})

describe("withNotification", () => {
  it("puts the newest first", () => {
    const history = withNotification([entry("a")], entry("b"))
    expect(history.map((n) => n.id)).toEqual(["b", "a"])
  })

  it("drops the oldest past the cap rather than growing forever", () => {
    let history: AppNotification[] = []
    for (let index = 0; index < 5; index += 1) {
      history = withNotification(history, entry(String(index)), 3)
    }
    expect(history.map((n) => n.id)).toEqual(["4", "3", "2"])
  })

  it("caps at the Mac's 200 by default", () => {
    expect(NOTIFICATION_LIMIT).toBe(200)
  })
})

describe("relativeTime", () => {
  it("reads as a person would say it", () => {
    const now = 1_000_000_000
    expect(relativeTime(now, now)).toBe("just now")
    expect(relativeTime(now - 30_000, now)).toBe("just now")
    expect(relativeTime(now - 4 * 60_000, now)).toBe("4m ago")
    expect(relativeTime(now - 2 * 3_600_000, now)).toBe("2h ago")
    expect(relativeTime(now - 3 * 86_400_000, now)).toBe("3d ago")
  })

  it("never reads as being in the future when the clocks disagree", () => {
    expect(relativeTime(2000, 1000)).toBe("just now")
  })

  it("never says 0m — the minute bucket starts at one", () => {
    expect(relativeTime(1_000_000_000 - 50_000, 1_000_000_000)).toBe("1m ago")
  })
})

describe("badgeText", () => {
  it("shows nothing at zero and stops counting past 99", () => {
    expect(badgeText(0)).toBeNull()
    expect(badgeText(-1)).toBeNull()
    expect(badgeText(7)).toBe("7")
    expect(badgeText(99)).toBe("99")
    expect(badgeText(100)).toBe("99+")
  })
})

/** A kept success — the shape an install's summary has. */
const installed = () => toToast({ message: "Installed app.apk", ok: true, important: true }, "t1")

describe("systemNotification", () => {
  it("says nothing while the window is the one being looked at", () => {
    expect(systemNotification(installed(), false)).toBeNull()
  })

  it("mirrors an important result once the window is not", () => {
    expect(systemNotification(installed(), true)).toEqual({
      title: "Task finished",
      body: "Installed app.apk",
      sound: false,
    })
  })

  it("stays quiet for a routine confirmation, which is not kept either", () => {
    const copied = toToast({ message: "Copied", ok: true }, "t2")
    expect(copied.notifiesWhenBackgrounded).toBe(false)
    expect(systemNotification(copied, true)).toBeNull()
  })

  it("carries a sound only for a failure", () => {
    const failed = toToast({ message: "adb refused it", ok: false }, "t3")
    expect(systemNotification(failed, true)).toEqual({
      title: "Task failed",
      body: "adb refused it",
      sound: true,
    })
  })

  it("lets a batch opt its members out while staying in the history", () => {
    const member = toToast(
      { message: "Installed one of four", ok: true, important: true, notifiesWhenBackgrounded: false },
      "t4",
    )
    expect(member.important).toBe(true)
    expect(systemNotification(member, true)).toBeNull()
  })
})

describe("systemTitle", () => {
  it("is SystemNotifier's three titles", () => {
    expect(systemTitle("success")).toBe("Task finished")
    expect(systemTitle("error")).toBe("Task failed")
    expect(systemTitle("warning")).toBe("Droidective")
    expect(systemTitle("info")).toBe("Droidective")
  })
})
