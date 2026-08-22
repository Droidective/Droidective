import { describe, expect, it } from "vitest"
import {
  formatBytes,
  infoRows,
  memoryHeadline,
  permissionMatches,
  pulledApkMessage,
  sandboxParent,
  sandboxRoot,
} from "@/lib/appinfo"
import type { AppInfoResponse, MemInfoResponse } from "@/lib/wire"

const info = (over: Partial<AppInfoResponse> = {}): AppInfoResponse => ({
  installed: true,
  versionName: "1.4.0",
  versionCode: "1400",
  targetSdk: "34",
  minSdk: "26",
  firstInstall: "2026-01-02",
  lastUpdate: "2026-06-01",
  apkPath: "/data/app/base.apk",
  apkSizeBytes: 12_345,
  ...over,
})

describe("infoRows", () => {
  it("lists the Mac's rows in the Mac's order", () => {
    expect(infoRows(info()).map((row) => row.label)).toEqual([
      "Version",
      "Version Code",
      "Target SDK",
      "Min SDK",
      "First Install",
      "Last Update",
      "APK Size",
    ])
  })

  it("leaves APK Size out when the device did not report one", () => {
    // A "—" there reads as a failed lookup rather than as a package manager
    // that simply did not say.
    const rows = infoRows(info({ apkSizeBytes: null }))
    expect(rows.map((row) => row.label)).not.toContain("APK Size")
  })
})

describe("formatBytes", () => {
  it("uses decimal units, as ByteCountFormatter(.file) does", () => {
    // Not KiB: the Mac prints decimal, and the same APK reading two different
    // sizes on two platforms is exactly the kind of difference this port
    // exists to avoid.
    expect(formatBytes(12_345)).toBe("12.3 kB")
    expect(formatBytes(5_400_000)).toBe("5.4 MB")
    expect(formatBytes(2_100_000_000)).toBe("2.1 GB")
  })

  it("spells out a small count rather than showing 0.0 kB", () => {
    expect(formatBytes(0)).toBe("0 bytes")
    expect(formatBytes(999)).toBe("999 bytes")
  })

  it("does not run off the end of its units", () => {
    expect(formatBytes(9e18)).toContain("TB")
  })
})

describe("pulledApkMessage", () => {
  it("says just APK for a single-file app", () => {
    expect(pulledApkMessage(["/tmp/base.apk"])).toBe("APK saved")
  })

  it("counts the splits a bundle install saved beside it", () => {
    expect(pulledApkMessage(["/a", "/b"])).toBe("APK + 1 split saved")
    expect(pulledApkMessage(["/a", "/b", "/c"])).toBe("APK + 2 splits saved")
  })

  it("does not claim a negative split count for an empty answer", () => {
    expect(pulledApkMessage([])).toBe("APK saved")
  })
})

const mem = (over: Partial<MemInfoResponse> = {}): MemInfoResponse => ({
  running: true,
  totalPssKb: 84_120,
  summary: [],
  ...over,
})

describe("memoryHeadline", () => {
  it("shows the total as a size", () => {
    expect(memoryHeadline(mem())).toBe("84.1 MB")
  })

  it("says a stopped app is stopped rather than showing zero", () => {
    expect(memoryHeadline(mem({ running: false, totalPssKb: null }))).toBe("Not running")
  })

  it("distinguishes running-but-silent from stopped", () => {
    expect(memoryHeadline(mem({ totalPssKb: null }))).toBe("No memory reported")
  })
})

describe("permissionMatches", () => {
  const camera = { name: "android.permission.CAMERA", shortName: "CAMERA" }

  it("matches the short name and the full one", () => {
    // People search for "CAMERA" and paste the full name in about equal
    // measure, so both have to hit.
    expect(permissionMatches(camera, "camera")).toBe(true)
    expect(permissionMatches(camera, "android.permission.CAM")).toBe(true)
  })

  it("matches everything on an empty or whitespace query", () => {
    expect(permissionMatches(camera, "")).toBe(true)
    expect(permissionMatches(camera, "   ")).toBe(true)
  })

  it("does not match something else", () => {
    expect(permissionMatches(camera, "location")).toBe(false)
  })
})

describe("sandboxParent", () => {
  const root = sandboxRoot("com.example.app")

  it("walks up one level", () => {
    expect(sandboxParent(`${root}/databases/inner`, root)).toBe(`${root}/databases`)
    expect(sandboxParent(`${root}/databases`, root)).toBe(root)
  })

  it("stops at the app's own root", () => {
    // Walking past it would leave the sandbox entirely, and `run-as` would
    // refuse — an "Up" button that errors is worse than one that stops.
    expect(sandboxParent(root, root)).toBeNull()
  })

  it("refuses a path that is not inside the sandbox at all", () => {
    expect(sandboxParent("/sdcard/Download", root)).toBeNull()
  })
})
