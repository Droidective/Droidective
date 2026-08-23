import { describe, expect, it } from "vitest"
import {
  effectiveRunOnAll,
  readyDevices,
  showsRunAll,
  summarise,
  supportsRunAll,
  targetSerials,
} from "@/lib/targets"
import type { Device, FeatureSummary } from "@/lib/wire"

function device(serial: string, state = "device"): Device {
  return {
    serial,
    state,
    model: null,
    product: null,
    transportId: null,
    label: serial,
    isWireless: false,
    platform: "android",
  }
}

function feature(runAll: boolean): FeatureSummary {
  return {
    id: "send-text",
    title: "Send Text",
    subtitle: null,
    keywords: [],
    category: "input",
    kind: "formAction",
    implemented: true,
    needsDevice: true,
    needsBundle: false,
    isDestructive: false,
    isAbsorbedByHub: false,
    supportsRunAll: runAll,
    fields: [],
  }
}

const two = [device("A"), device("B")]

describe("readyDevices", () => {
  it("counts only what adb will talk to", () => {
    const mixed = [device("A"), device("B", "unauthorized"), device("C", "offline")]
    expect(readyDevices(mixed).map((entry) => entry.serial)).toEqual(["A"])
  })
})

describe("supportsRunAll", () => {
  it("takes the registry's answer, and no feature is no", () => {
    expect(supportsRunAll(feature(true))).toBe(true)
    expect(supportsRunAll(feature(false))).toBe(false)
    // Home, or a tab whose feature has gone away.
    expect(supportsRunAll(null)).toBe(false)
  })
})

describe("effectiveRunOnAll", () => {
  it("needs the toggle and the feature to agree", () => {
    expect(effectiveRunOnAll(true, feature(true))).toBe(true)
    // The case worth defending: a toggle left on from Send Text must not fan
    // the next feature out too.
    expect(effectiveRunOnAll(true, feature(false))).toBe(false)
    expect(effectiveRunOnAll(false, feature(true))).toBe(false)
  })
})

describe("showsRunAll", () => {
  it("offers the choice only when there is a choice", () => {
    expect(showsRunAll(two, feature(true))).toBe(true)
    // One device is not a fan-out.
    expect(showsRunAll([device("A")], feature(true))).toBe(false)
    expect(showsRunAll([device("A"), device("B", "offline")], feature(true))).toBe(false)
    expect(showsRunAll(two, feature(false))).toBe(false)
  })
})

describe("targetSerials", () => {
  it("is the selected device when run-on-all is off", () => {
    expect(targetSerials(two, device("B"), false)).toEqual(["B"])
  })

  it("is every ready device, selected first, when it is on", () => {
    // First because a fan-out reports per device and the bar's device is the
    // one being watched.
    expect(targetSerials(two, device("B"), true)).toEqual(["B", "A"])
  })

  it("leaves out devices adb cannot reach", () => {
    const mixed = [device("A"), device("B", "unauthorized"), device("C")]
    expect(targetSerials(mixed, device("A"), true)).toEqual(["A", "C"])
  })

  it("targets nothing when the selection is not ready", () => {
    // Better than a call adb refuses with a message about a serial.
    expect(targetSerials([device("A", "offline")], device("A", "offline"), false)).toEqual([])
  })

  it("still fans out when nothing is selected", () => {
    expect(targetSerials(two, null, true)).toEqual(["A", "B"])
    expect(targetSerials(two, null, false)).toEqual([])
  })
})

describe("summarise", () => {
  it("leaves one device's own message alone", () => {
    // The single-device case is most of the app; it must not grow a summary.
    expect(summarise([{ serial: "A", ok: true, message: "Sent" }])).toEqual({
      ok: true,
      message: "Sent",
    })
  })

  it("counts a clean fan-out", () => {
    expect(
      summarise([
        { serial: "A", ok: true, message: "Sent" },
        { serial: "B", ok: true, message: "Sent" },
      ]),
    ).toEqual({ ok: true, message: "Ran on 2 devices" })
  })

  it("names the devices that failed rather than counting them", () => {
    const summary = summarise([
      { serial: "A", ok: true, message: "Sent" },
      { serial: "B", ok: false, message: "closed" },
      { serial: "C", ok: false, message: "closed" },
    ])
    expect(summary.ok).toBe(false)
    expect(summary.message).toBe("Ran on 1 of 3 — failed on B, C")
  })

  it("says so when there was nothing to run on", () => {
    expect(summarise([])).toEqual({ ok: false, message: "No device connected." })
  })
})
