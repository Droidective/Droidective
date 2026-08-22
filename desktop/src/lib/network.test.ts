import { describe, expect, it } from "vitest"
import {
  canApplyDns,
  canConnect,
  DNS_MODES,
  revealedPassword,
  savedEmptyText,
  SECURITY_MODES,
  wifiDetail,
  wifiHeadline,
} from "@/lib/network"
import type { SavedNetwork, WifiStatus } from "@/lib/wire"

const status = (over: Partial<WifiStatus> = {}): WifiStatus => ({
  enabled: true,
  connected: true,
  ssid: "Coffee",
  ipAddress: "192.168.1.9",
  linkSpeed: "780Mbps",
  frequency: "5GHz",
  signal: "-42dBm",
  ...over,
})

describe("wifiHeadline", () => {
  it("shows the network's name when there is one", () => {
    expect(wifiHeadline(status())).toBe("Coffee")
  })

  it("tells the two failure modes apart", () => {
    // "Not connected" and "Wi-Fi off" are different problems — one needs a
    // network picked, the other needs the radio on.
    expect(wifiHeadline(status({ ssid: null, enabled: true }))).toBe("Not connected")
    expect(wifiHeadline(status({ ssid: null, enabled: false }))).toBe("Wi-Fi off")
  })

  it("treats an empty ssid as no ssid", () => {
    expect(wifiHeadline(status({ ssid: "" }))).toBe("Not connected")
  })

  it("says something before the first read lands", () => {
    expect(wifiHeadline(null)).toBe("Wi-Fi off")
  })
})

describe("wifiDetail", () => {
  it("joins what the device reported with the Mac's separator", () => {
    expect(wifiDetail(status())).toBe("192.168.1.9 · 780Mbps · 5GHz · -42dBm")
  })

  it("leaves out what the device did not report, without a stray separator", () => {
    // A lone " · " where a value should be reads as a bug.
    expect(wifiDetail(status({ linkSpeed: null, signal: null }))).toBe("192.168.1.9 · 5GHz")
  })

  it("says nothing at all while disconnected", () => {
    expect(wifiDetail(status({ connected: false }))).toBe("")
    expect(wifiDetail(null)).toBe("")
  })
})

describe("SECURITY_MODES", () => {
  it("offers the Mac's three, in its order", () => {
    expect(SECURITY_MODES.map((mode) => mode.value)).toEqual(["wpa2", "wpa3", "open"])
    expect(SECURITY_MODES.map((mode) => mode.label)).toEqual(["WPA2", "WPA3", "Open"])
  })
})

describe("canConnect", () => {
  it("needs an ssid that is more than whitespace", () => {
    expect(canConnect("Coffee", false)).toBe(true)
    expect(canConnect("", false)).toBe(false)
    expect(canConnect("   ", false)).toBe(false)
  })

  it("is off while a command is already running", () => {
    expect(canConnect("Coffee", true)).toBe(false)
  })
})

const net = (password: string | null): SavedNetwork => ({
  id: "1",
  ssid: "Coffee",
  security: "WPA2",
  password,
})

describe("revealedPassword", () => {
  it("masks until asked", () => {
    expect(revealedPassword(net("hunter2"), false)).toBe("••••••••")
    expect(revealedPassword(net("hunter2"), true)).toBe("hunter2")
  })

  it("shows nothing at all when there is no password to hide", () => {
    // An unrooted device reports no passwords; a row of dots there would
    // claim there is one behind them.
    expect(revealedPassword(net(null), true)).toBeNull()
    expect(revealedPassword(net(""), true)).toBeNull()
  })
})

describe("savedEmptyText", () => {
  it("distinguishes still-loading from genuinely none", () => {
    expect(savedEmptyText(false)).toBe("Loading…")
    expect(savedEmptyText(true)).toContain("Android 11+")
  })
})

describe("DNS_MODES", () => {
  it("offers the Mac's three, in its order", () => {
    expect(DNS_MODES.map((mode) => mode.value)).toEqual(["off", "automatic", "hostname"])
  })
})

describe("canApplyDns", () => {
  it("needs a hostname only in hostname mode", () => {
    expect(canApplyDns("off", "", true)).toBe(true)
    expect(canApplyDns("automatic", "", true)).toBe(true)
    expect(canApplyDns("hostname", "", true)).toBe(false)
    expect(canApplyDns("hostname", "   ", true)).toBe(false)
    expect(canApplyDns("hostname", "dns.google", true)).toBe(true)
  })

  it("is off until the current setting has been read", () => {
    // Applying over a value nobody has seen yet would overwrite it blind.
    expect(canApplyDns("off", "", false)).toBe(false)
  })
})
