import { describe, expect, it } from "vitest"
import {
  adbMissing,
  blocking,
  CHECKS,
  checkedTools,
  installCommand,
  verdict,
} from "@/lib/doctor"
import type { ToolReport } from "@/lib/wire"

function tool(id: string, installed: boolean): ToolReport {
  return {
    id,
    installed,
    path: installed ? `/usr/bin/${id}` : null,
    version: installed ? "1.0" : null,
    installHint: `Install ${id}`,
  }
}

describe("checkedTools", () => {
  it("lists the Doctor's own two, in its order", () => {
    expect(CHECKS.map((check) => check.id)).toEqual(["adb", "emulator"])
    const rows = checkedTools([tool("emulator", true), tool("adb", false), tool("ffmpeg", true)])
    // The daemon's order is the registry's; the Doctor's is its own.
    expect(rows.map((row) => row.check.id)).toEqual(["adb", "emulator"])
  })

  it("pairs a check with nothing when the report has no row for it", () => {
    const rows = checkedTools([tool("adb", true)])
    expect(rows[0]?.report?.installed).toBe(true)
    expect(rows[1]?.report).toBeNull()
  })

  it("ignores the tools it does not check", () => {
    // scrcpy and ffmpeg block nothing here, as on the Mac.
    const rows = checkedTools([tool("scrcpy", false), tool("ffmpeg", false)])
    expect(rows.every((row) => row.report === null)).toBe(true)
  })
})

describe("blocking", () => {
  it("counts only missing checked tools", () => {
    const report = [tool("adb", true), tool("emulator", false), tool("scrcpy", false)]
    expect(blocking(report).map((entry) => entry.id)).toEqual(["emulator"])
  })
})

describe("verdict", () => {
  it("is still looking before anything has been checked", () => {
    // Claiming everything is installed before checking is the one wrong answer.
    expect(verdict([])).toEqual({ tone: "pending", message: "Checking your setup…" })
  })

  it("is all-set when both are there", () => {
    expect(verdict([tool("adb", true), tool("emulator", true)]).tone).toBe("ok")
  })

  it("counts what is missing, and gets the plural right", () => {
    expect(verdict([tool("adb", false), tool("emulator", true)]).message).toBe(
      "1 tool missing — some features won't work until installed.",
    )
    expect(verdict([tool("adb", false), tool("emulator", false)]).message).toBe(
      "2 tools missing — some features won't work until installed.",
    )
  })

  it("is all-set even with an unchecked tool missing", () => {
    expect(verdict([tool("adb", true), tool("emulator", true), tool("scrcpy", false)]).tone).toBe(
      "ok",
    )
  })
})

describe("adbMissing", () => {
  it("answers nothing until adb has been looked for", () => {
    // The bar must not flash a warning during startup.
    expect(adbMissing([])).toBeNull()
    expect(adbMissing([tool("emulator", true)])).toBeNull()
  })

  it("answers once it has", () => {
    expect(adbMissing([tool("adb", false)])).toBe(true)
    expect(adbMissing([tool("adb", true)])).toBe(false)
  })
})

describe("installCommand", () => {
  /**
   * The daemon words each hint for the machine it runs on, and this is what
   * lets the UI offer the useful half rather than making somebody retype it
   * out of a tooltip.
   */
  it("pulls the command out of a hint that names one", () => {
    expect(
      installCommand("adb is missing. Install it with `sudo apt install android-tools-adb`, then re-check."),
    ).toBe("sudo apt install android-tools-adb")
    expect(installCommand("adb is missing. Install it with `winget install Google.PlatformTools`, or …")).toBe(
      "winget install Google.PlatformTools",
    )
  })

  /** A hint that only points at a web page has no command to copy. */
  it("is null when the hint names no command", () => {
    expect(installCommand("Install Android platform-tools — via Android Studio, or from …")).toBeNull()
    expect(installCommand("")).toBeNull()
  })

  /** An empty pair of backticks is not a command. */
  it("refuses an empty quote rather than copying nothing", () => {
    expect(installCommand("install it with `` then re-check")).toBeNull()
    expect(installCommand("install it with `   ` then re-check")).toBeNull()
  })
})
