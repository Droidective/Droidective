import { describe, expect, it } from "vitest"

import {
  canPrepareForTailscale,
  deviceTitle,
  isTailnetAddress,
  isTailnetSerial,
  linkCutQuestion,
  prepareTitle,
} from "@/lib/tailnet"
import type { Device } from "@/lib/wire"

function device(over: Partial<Device> = {}): Device {
  return {
    serial: "R58M123ABC",
    state: "device",
    model: "Pixel 7",
    product: null,
    transportId: null,
    label: "Pixel 7 (3ABC)",
    isWireless: false,
    platform: "android",
    ...over,
  }
}

const REMOTE = device({
  serial: "100.101.102.103:5555",
  label: "Pixel 7 (5555)",
  isWireless: true,
})

// The vectors are ADBKit's `TailnetAddressTests`, so the two cannot drift.
describe("isTailnetAddress", () => {
  it("is 100.64.0.0/10", () => {
    expect(isTailnetAddress("100.64.0.0")).toBe(true)
    expect(isTailnetAddress("100.127.255.255")).toBe(true)
    expect(isTailnetAddress("100.63.255.255")).toBe(false)
    expect(isTailnetAddress("100.128.0.0")).toBe(false)
    expect(isTailnetAddress("192.168.1.20")).toBe(false)
  })

  it("refuses what is not quite an address", () => {
    for (const text of [
      "100.64.1",
      "100.64.1.256",
      "100.64.1.1.1",
      "100.64..1",
      "１００.64.1.1",
      "100.+64.1.1",
      "",
    ]) {
      expect(isTailnetAddress(text), text).toBe(false)
    }
  })
})

describe("isTailnetSerial", () => {
  it("is only an ip:port serial on the tailnet", () => {
    expect(isTailnetSerial("100.101.102.103:5555")).toBe(true)
    for (const serial of [
      "192.168.1.20:5555",
      "100.101.102.103",
      "100.101.102.103:",
      "emulator-5554",
      "R58M123ABC",
      "adb-R58M-abc._adb-tls-connect._tcp",
    ]) {
      expect(isTailnetSerial(serial), serial).toBe(false)
    }
  })
})

describe("deviceTitle", () => {
  it("ends a ready tailnet phone's title with Tailscale, as the Mac does", () => {
    expect(deviceTitle(REMOTE)).toBe("Pixel 7 (5555) · Tailscale")
    expect(deviceTitle(device())).toBe("Pixel 7 (3ABC)")
    expect(deviceTitle(device({ serial: "192.168.1.20:5555", isWireless: true }))).toBe(
      "Pixel 7 (3ABC)",
    )
  })

  it("still says what is wrong with a device that is not ready", () => {
    expect(deviceTitle({ ...REMOTE, state: "offline" })).toBe("Pixel 7 (5555) — offline")
  })
})

describe("linkCutQuestion", () => {
  const warning = "Turning Wi-Fi off or joining another network can take it off your tailnet."

  it("asks on a tailnet phone, naming it and the risk", () => {
    expect(linkCutQuestion(warning, [REMOTE.serial], [REMOTE])).toEqual({
      title: "Pixel 7 (5555) is connected over Tailscale",
      message: `${warning} If the link drops, reconnecting needs the phone in hand.`,
    })
  })

  it("finds the tailnet phone among several targets", () => {
    const question = linkCutQuestion(warning, ["R58M123ABC", REMOTE.serial], [device(), REMOTE])
    expect(question?.title).toBe("Pixel 7 (5555) is connected over Tailscale")
  })

  it("names the serial when the device is not in the list", () => {
    expect(linkCutQuestion(warning, [REMOTE.serial], [])?.title).toBe(
      "100.101.102.103:5555 is connected over Tailscale",
    )
  })

  it("does not ask on a cabled or local-network phone, or for an unflagged feature", () => {
    expect(linkCutQuestion(warning, ["R58M123ABC", "192.168.1.20:5555"], [])).toBeNull()
    expect(linkCutQuestion(warning, [], [])).toBeNull()
    expect(linkCutQuestion(null, [REMOTE.serial], [REMOTE])).toBeNull()
    expect(linkCutQuestion(undefined, [REMOTE.serial], [REMOTE])).toBeNull()
  })
})

describe("canPrepareForTailscale", () => {
  it("is a ready Android phone on a cable", () => {
    expect(canPrepareForTailscale(device())).toBe(true)
  })

  it("is not a wireless phone, an emulator, a simulator, or one that is not ready", () => {
    expect(canPrepareForTailscale(null)).toBe(false)
    expect(canPrepareForTailscale(REMOTE)).toBe(false)
    expect(canPrepareForTailscale(device({ serial: "emulator-5560" }))).toBe(false)
    expect(canPrepareForTailscale(device({ platform: "ios-simulator" }))).toBe(false)
    expect(canPrepareForTailscale(device({ state: "unauthorized" }))).toBe(false)
  })

  it("titles its confirmation the Mac's way", () => {
    expect(prepareTitle("Pixel 7 (3ABC)")).toBe("Prepare Pixel 7 (3ABC) for Tailscale?")
  })
})
