import { describe, expect, it } from "vitest"
import {
  formatKb,
  formatNumber,
  formatRate,
  HISTORY_LIMIT,
  peak,
  perCore,
  polyline,
  ramPercent,
  recordLabel,
  series,
  statusText,
  tableProcesses,
  timed,
  toCsv,
  toJson,
  totalCpu,
  withSample,
} from "@/lib/performance"
import type { PerfSample } from "@/lib/wire"

function sample(overrides: Partial<PerfSample> = {}): PerfSample {
  return {
    cores: [
      { core: -1, label: "All cores", usagePercent: 40 },
      { core: 0, label: "Core 0", usagePercent: 30 },
      { core: 1, label: "Core 1", usagePercent: 50 },
    ],
    ramTotalKb: 8_000_000,
    ramUsedKb: 2_000_000,
    appFps: 59.4,
    appJankPercent: 3.2,
    appPssKb: 150_000,
    downloadBytesPerSec: 2048,
    uploadBytesPerSec: 512,
    processes: [],
    ...overrides,
  }
}

describe("withSample", () => {
  it("keeps the newest window and drops the oldest", () => {
    let history: PerfSample[] = []
    for (let index = 0; index < 5; index += 1) {
      history = withSample(history, sample({ appFps: index }), 3)
    }
    expect(history.map((s) => s.appFps)).toEqual([2, 3, 4])
  })

  it("defaults to five minutes at one sample a second", () => {
    expect(HISTORY_LIMIT).toBe(300)
  })
})

describe("totalCpu", () => {
  it("uses the device's own all-cores figure when there is one", () => {
    expect(totalCpu(sample())).toBe(40)
  })

  it("averages the cores when the device reported no aggregate", () => {
    // Showing nothing would be worse than showing the same number derived.
    const perCoreOnly = sample({
      cores: [
        { core: 0, label: "Core 0", usagePercent: 30 },
        { core: 1, label: "Core 1", usagePercent: 50 },
      ],
    })
    expect(totalCpu(perCoreOnly)).toBe(40)
  })

  it("is null on the first sample, which has no delta to report", () => {
    expect(totalCpu(sample({ cores: [] }))).toBeNull()
  })
})

describe("perCore", () => {
  it("drops the aggregate and sorts by core number", () => {
    const shuffled = sample({
      cores: [
        { core: 1, label: "Core 1", usagePercent: 50 },
        { core: -1, label: "All cores", usagePercent: 40 },
        { core: 0, label: "Core 0", usagePercent: 30 },
      ],
    })
    expect(perCore(shuffled).map((core) => core.core)).toEqual([0, 1])
  })
})

describe("ramPercent", () => {
  it("is the used share of the total", () => {
    expect(ramPercent(sample())).toBe(25)
  })

  it("is null when the device did not answer, and never divides by zero", () => {
    expect(ramPercent(sample({ ramUsedKb: null }))).toBeNull()
    expect(ramPercent(sample({ ramTotalKb: null }))).toBeNull()
    expect(ramPercent(sample({ ramTotalKb: 0 }))).toBeNull()
  })
})

describe("series", () => {
  it("scales to fractions of the given max", () => {
    const history = [sample({ appFps: 30 }), sample({ appFps: 60 })]
    expect(series(history, (s) => s.appFps, 60)).toEqual([0.5, 1])
  })

  it("clamps above the max rather than drawing off the chart", () => {
    expect(series([sample({ appFps: 120 })], (s) => s.appFps, 60)).toEqual([1])
  })

  it("reads a missing value as zero rather than a hole", () => {
    expect(series([sample({ appFps: null })], (s) => s.appFps, 60)).toEqual([0])
  })

  it("does not divide by a zero max", () => {
    expect(series([sample()], (s) => s.appFps, 0)).toEqual([0])
  })
})

describe("polyline", () => {
  it("spans the viewBox and flips the y axis", () => {
    // SVG y grows downward, so a full-height value is y=0.
    expect(polyline([0, 1])).toBe("0,100 100,0")
    expect(polyline([0.5, 0.5, 0.5])).toBe("0,50 50,50 100,50")
  })

  it("draws one sample as a flat line rather than a point nobody can see", () => {
    expect(polyline([0.25])).toBe("0,75 100,75")
  })

  it("draws nothing for no samples", () => {
    expect(polyline([])).toBe("")
  })
})

describe("peak", () => {
  it("finds the highest value, ignoring the ones the device skipped", () => {
    const history = [sample({ appFps: 30 }), sample({ appFps: null }), sample({ appFps: 58 })]
    expect(peak(history, (s) => s.appFps)).toBe(58)
  })

  it("is zero for an empty history, so a chart divides by its own floor", () => {
    expect(peak<PerfSample>([], (s) => s.appFps)).toBe(0)
  })
})

describe("formatting", () => {
  it("reads kilobytes in binary units, the way a device reports memory", () => {
    expect(formatKb(512)).toBe("512 KB")
    expect(formatKb(2048)).toBe("2 MB")
    expect(formatKb(8_000_000)).toBe("7.6 GB")
    expect(formatKb(null)).toBe("—")
    expect(formatKb(0)).toBe("—")
  })

  it("reads a throughput per second", () => {
    expect(formatRate(512)).toBe("512 B/s")
    expect(formatRate(2048)).toBe("2 KB/s")
    expect(formatRate(null)).toBe("—")
  })

  it("dashes a figure the device never gave rather than printing zero", () => {
    // A missing FPS is not 0 FPS, and a chart that says so is lying.
    expect(formatNumber(null, " fps")).toBe("—")
    expect(formatNumber(59.44, " fps")).toBe("59.4 fps")
  })
})

const busyProcesses = sample({
  processes: [
    { pid: 1, name: "quiet", cpuPercent: 0, pssKb: 900 },
    { pid: 2, name: "busy", cpuPercent: 40, pssKb: 100 },
    { pid: 3, name: "idle-fat", cpuPercent: 0, pssKb: 5000 },
  ],
})

describe("tableProcesses", () => {
  it("defaults to RAM, which is what a leak hunt wants", () => {
    expect(tableProcesses(busyProcesses, "", "RAM").map((p) => p.name)).toEqual([
      "idle-fat",
      "quiet",
      "busy",
    ])
  })

  it("sorts by CPU and by name too", () => {
    expect(tableProcesses(busyProcesses, "", "CPU")[0]?.name).toBe("busy")
    expect(tableProcesses(busyProcesses, "", "Name").map((p) => p.name)).toEqual([
      "busy",
      "idle-fat",
      "quiet",
    ])
  })

  it("filters by name, case-insensitively", () => {
    expect(tableProcesses(busyProcesses, "FAT", "RAM").map((p) => p.name)).toEqual(["idle-fat"])
    expect(tableProcesses(busyProcesses, "nothing", "RAM")).toEqual([])
  })

  it("treats a figure the device never gave as zero rather than dropping the row", () => {
    const unknown = sample({
      processes: [{ pid: 1, name: "unknown", cpuPercent: null, pssKb: null }],
    })
    expect(tableProcesses(unknown, "", "CPU")).toHaveLength(1)
  })

  it("has nothing to show before the first sample", () => {
    expect(tableProcesses(null, "", "RAM")).toEqual([])
  })
})

describe("the recording clock", () => {
  it("derives elapsed from the sample's place, not a host clock", () => {
    // The daemon sends no timestamp; the interval is fixed, so the count is
    // the elapsed time — and the export says so.
    expect(timed(sample(), 0).elapsed).toBe(0)
    expect(timed(sample(), 90).elapsed).toBe(90)
  })

  it("reads the way the Mac's status line reads", () => {
    const at = (seconds: number) => [timed(sample(), seconds)]
    expect(statusText("idle", [])).toBe("Ready")
    expect(statusText("idle", at(83))).toBe("Stopped · 01:23")
    expect(statusText("recording", at(83))).toBe("Recording · 01:23")
    expect(statusText("paused", at(5))).toBe("Paused · 00:05")
  })

  it("names the Record button for what pressing it does next", () => {
    expect(recordLabel("idle")).toBe("Record")
    expect(recordLabel("recording")).toBe("Pause")
    expect(recordLabel("paused")).toBe("Resume")
  })
})

describe("toJson", () => {
  it("carries the device, the app and the interval alongside the samples", () => {
    const report: unknown = JSON.parse(
      toJson([timed(sample(), 0)], { serial: "emulator-5554", packageId: "com.example.app" }),
    )
    expect(report).toMatchObject({
      device: "emulator-5554",
      package: "com.example.app",
      intervalSeconds: 1,
    })
  })

  it("keeps the per-process rows a CSV row cannot hold", () => {
    const withProcesses = timed(busyProcesses, 0)
    expect(toJson([withProcesses], { serial: "S1", packageId: null })).toContain("idle-fat")
  })
})

describe("toCsv", () => {
  it("writes one row per sample, stamped with its elapsed seconds", () => {
    const csv = toCsv([timed(sample(), 0), timed(sample({ appFps: 30 }), 1)])
    const lines = csv.split("\n")
    expect(lines[0]).toBe("# one sample every 1s")
    expect(lines[1]).toBe(
      "elapsedSeconds,cpuPercent,ramUsedKb,ramTotalKb,fps,jankPercent,appPssKb,downloadBytesPerSec,uploadBytesPerSec",
    )
    expect(lines[2]).toBe("0,40,2000000,8000000,59.4,3.2,150000,2048,512")
    expect(lines[3]?.startsWith("1,")).toBe(true)
  })

  it("leaves a figure the device never gave empty rather than writing 0", () => {
    const csv = toCsv([timed(sample({ appFps: null, appPssKb: null }), 0)])
    expect(csv.split("\n")[2]).toBe("0,40,2000000,8000000,,3.2,,2048,512")
  })

  it("writes just the header for an empty recording", () => {
    expect(toCsv([]).split("\n")).toHaveLength(2)
  })
})
