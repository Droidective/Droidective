import { describe, expect, it } from "vitest"
import { arm, CONFIRM_WINDOW_MS, isArmed } from "@/lib/confirm"

describe("isArmed", () => {
  const armed = arm("clear-data", "com.example.app", 1000)

  it("authorises the same button on the same target, straight away", () => {
    expect(isArmed(armed, "clear-data", "com.example.app", 1000)).toBe(true)
  })

  it("authorises nothing when nothing is armed", () => {
    expect(isArmed(null, "clear-data", "com.example.app", 1000)).toBe(false)
  })

  it("does not carry over to a different button", () => {
    // Arming Clear Data must not authorise Uninstall stood next to it.
    expect(isArmed(armed, "uninstall", "com.example.app", 1000)).toBe(false)
  })

  it("does not carry over to a different app", () => {
    // The scenario worth preventing: arm on one app, pick another, press
    // again, and wipe the wrong one.
    expect(isArmed(armed, "clear-data", "com.other.app", 1000)).toBe(false)
  })

  it("expires", () => {
    expect(isArmed(armed, "clear-data", "com.example.app", 1000 + CONFIRM_WINDOW_MS - 1)).toBe(true)
    expect(isArmed(armed, "clear-data", "com.example.app", 1000 + CONFIRM_WINDOW_MS)).toBe(false)
    expect(isArmed(armed, "clear-data", "com.example.app", 1000 + 600_000)).toBe(false)
  })
})
