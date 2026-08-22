import { describe, expect, it } from "vitest"
import {
  activeInterfaces,
  chartMax,
  MAX_SAMPLES,
  sessionTotals,
  statusText,
  timed,
  toCsv,
  toJson,
  withSample,
} from "@/lib/netspeed"
import type { NetSample } from "@/lib/wire"

const sample = (over: Partial<NetSample> = {}): NetSample => ({
  downloadBytesPerSec: 1024,
  uploadBytesPerSec: 512,
  totalRxBytes: 1_000_000,
  totalTxBytes: 500_000,
  interfaces: [],
  ...over,
})

describe("timed", () => {
  it("derives the clock from the sample's index", () => {
    // The daemon sends no timestamp and a host clock would be a time the
    // device never claimed; the interval is fixed, so the count is the time.
    expect(timed(sample(), 0).elapsed).toBe(0)
    expect(timed(sample(), 5).elapsed).toBe(5)
  })
})

describe("withSample", () => {
  it("drops the oldest past the window", () => {
    let history: number[] = []
    for (let index = 0; index < 5; index += 1) history = withSample(history, index, 3)
    expect(history).toEqual([2, 3, 4])
  })

  it("caps a recording so the monitor never becomes the load", () => {
    expect(MAX_SAMPLES).toBe(5000)
  })
})

describe("sessionTotals", () => {
  it("differences against the first sample, not the device's lifetime", () => {
    // The counters are since boot. Reporting them raw would show a
    // just-subscribed session as having moved gigabytes.
    const history = [
      sample({ totalRxBytes: 1_000_000, totalTxBytes: 500_000 }),
      sample({ totalRxBytes: 1_500_000, totalTxBytes: 600_000 }),
    ]
    expect(sessionTotals(history)).toEqual({ rx: 500_000, tx: 100_000 })
  })

  it("reads a counter reset as zero rather than as negative traffic", () => {
    const history = [sample({ totalRxBytes: 9_000_000 }), sample({ totalRxBytes: 12 })]
    expect(sessionTotals(history).rx).toBe(0)
  })

  it("is zero before anything has arrived", () => {
    expect(sessionTotals([])).toEqual({ rx: 0, tx: 0 })
  })
})

describe("statusText", () => {
  it("distinguishes watching from recording", () => {
    // Two independent states, as the Mac has: you can watch without keeping.
    expect(statusText(false, false, 0)).toBe("Idle")
    expect(statusText(true, false, 83)).toBe("Live · 01:23")
    expect(statusText(true, true, 83)).toBe("Recording · 01:23")
  })

  it("is idle even if a stale elapsed lingers", () => {
    expect(statusText(false, true, 99)).toBe("Idle")
  })
})

describe("chartMax", () => {
  it("leaves headroom above the peak", () => {
    const history = [sample({ downloadBytesPerSec: 1_000_000 })]
    expect(chartMax(history)).toBeCloseTo(1_200_000)
  })

  it("keeps a floor so an idle device is not drawn as a spike", () => {
    expect(chartMax([sample({ downloadBytesPerSec: 1, uploadBytesPerSec: 0 })])).toBe(64 * 1024)
    expect(chartMax([])).toBe(64 * 1024)
  })

  it("scales to whichever direction is busier", () => {
    const history = [sample({ downloadBytesPerSec: 0, uploadBytesPerSec: 2_000_000 })]
    expect(chartMax(history)).toBeCloseTo(2_400_000)
  })
})

const iface = (name: string, down: number, up: number) => ({
  name,
  downloadBytesPerSec: down,
  uploadBytesPerSec: up,
  rxBytes: 0,
  txBytes: 0,
})

describe("activeInterfaces", () => {
  it("lists only what moved something", () => {
    // A device reports a dozen interfaces and almost all of them are idle
    // loopback and rmnet stubs.
    const shown = activeInterfaces(
      sample({ interfaces: [iface("wlan0", 900, 100), iface("lo", 0, 0)] }),
    )
    expect(shown.map((entry) => entry.name)).toEqual(["wlan0"])
  })

  it("has nothing to list before the first sample", () => {
    expect(activeInterfaces(null)).toEqual([])
  })
})

describe("the exports", () => {
  const history = [timed(sample(), 0), timed(sample({ downloadBytesPerSec: 2048 }), 1)]

  it("writes JSON that says what it is a recording of", () => {
    const parsed = JSON.parse(toJson(history, "emulator-5554")) as {
      serial: string
      intervalSeconds: number
      samples: unknown[]
    }
    expect(parsed.serial).toBe("emulator-5554")
    expect(parsed.intervalSeconds).toBe(1)
    expect(parsed.samples).toHaveLength(2)
  })

  it("writes a CSV with a header and one row per sample", () => {
    const lines = toCsv(history).trimEnd().split("\n")
    expect(lines[0]).toBe("elapsed_s,download_bps,upload_bps,total_rx_bytes,total_tx_bytes")
    expect(lines).toHaveLength(3)
    expect(lines[2]).toBe("1,2048,512,1000000,500000")
  })

  it("writes a header-only CSV for an empty recording rather than nothing", () => {
    expect(toCsv([]).trimEnd().split("\n")).toHaveLength(1)
  })
})
