import { beforeEach, describe, expect, it } from "vitest"

import {
  installHeadline,
  openFailure,
  opensInStudio,
  readOpensApp,
  writeOpensApp,
} from "@/lib/install-app"
import type { InstallOutcome } from "@/lib/wire"

const ok = (serial: string, extra: Partial<InstallOutcome> = {}): InstallOutcome => ({
  serial,
  ok: true,
  message: "Installed",
  ...extra,
})

describe("installHeadline", () => {
  it("says the Mac's words for an install that landed", () => {
    expect(installHeadline("app.apk", [ok("S1")], false)).toEqual({
      ok: true,
      message: "Installed app.apk",
    })
    expect(installHeadline("app.apk", [ok("S1"), ok("S2")], false).message).toBe(
      "Installed app.apk on 2 devices",
    )
  })

  it("says it opened the app only when it opened everywhere it landed", () => {
    expect(installHeadline("app.apk", [ok("S1", { opened: true })], true).message).toBe(
      "Installed and opened app.apk",
    )
    const unopened = [ok("S1", { opened: false, openFailure: "No launcher activity" })]
    expect(installHeadline("app.apk", unopened, true).message).toBe("Installed app.apk")
  })

  it("names a single failure and counts several", () => {
    const failed: InstallOutcome = { serial: "S2", ok: false, message: "Not enough storage." }
    expect(installHeadline("app.apk", [failed], false)).toEqual({
      ok: false,
      message: "Couldn't install app.apk — Not enough storage.",
    })
    expect(installHeadline("app.apk", [ok("S1"), failed], false)).toEqual({
      ok: false,
      message: "Installed app.apk on 1/2 devices — 1 failed",
    })
  })
})

describe("openFailure", () => {
  it("is the first reason from a device the install reached", () => {
    expect(openFailure([ok("S1"), ok("S2", { openFailure: "No launcher" })])).toBe("No launcher")
    // A failed install has nothing to open, so its field means nothing.
    expect(openFailure([{ serial: "S1", ok: false, message: "x", openFailure: "y" }])).toBeNull()
    expect(openFailure([ok("S1", { openFailure: null })])).toBeNull()
  })
})

describe("opensInStudio", () => {
  it("takes a plain APK and no bundle", () => {
    expect(opensInStudio("/in/App.APK")).toBe(true)
    expect(opensInStudio("/in/app.xapk")).toBe(false)
    expect(opensInStudio("/in/app.apks")).toBe(false)
  })
})

describe("the remembered box", () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it("is off until ticked, then stays as it was left", () => {
    expect(readOpensApp()).toBe(false)
    writeOpensApp(true)
    expect(readOpensApp()).toBe(true)
    writeOpensApp(false)
    expect(readOpensApp()).toBe(false)
  })
})
