import { describe, expect, it } from "vitest"
import { hostPrefix, looksLikeEndpoint, looksLikePairEndpoint } from "@/lib/endpoint"

describe("looksLikeEndpoint", () => {
  it("accepts what the phone displays, and a bare host", () => {
    expect(looksLikeEndpoint("192.168.1.42:5555")).toBe(true)
    expect(looksLikeEndpoint("192.168.1.42")).toBe(true)
    expect(looksLikeEndpoint(" 192.168.1.42:5555 ")).toBe(true)
    expect(looksLikeEndpoint("[fe80::1]:40913")).toBe(true)
  })

  it("refuses nothing typed, and more than one token", () => {
    expect(looksLikeEndpoint("")).toBe(false)
    expect(looksLikeEndpoint("   ")).toBe(false)
    expect(looksLikeEndpoint("192.168.1.42 5555")).toBe(false)
  })

  it("stays out of the daemon's way on a host adb will refuse", () => {
    // A truncated IPv4 enables the button and comes back as adb's own answer,
    // which says more than a greyed-out button. The daemon is the authority.
    expect(looksLikeEndpoint("1.1.1")).toBe(true)
  })
})

describe("looksLikePairEndpoint", () => {
  it("needs the explicit pairing port", () => {
    // Random per session, so there is nothing to default to.
    expect(looksLikePairEndpoint("192.168.1.42:37123")).toBe(true)
    expect(looksLikePairEndpoint("192.168.1.42")).toBe(false)
    expect(looksLikePairEndpoint("192.168.1.42:")).toBe(false)
  })

  it("reads the port after a bracketed IPv6 host", () => {
    expect(looksLikePairEndpoint("[fe80::1]:37123")).toBe(true)
    expect(looksLikePairEndpoint("[fe80::1]")).toBe(false)
  })

  it("refuses a non-numeric port", () => {
    expect(looksLikePairEndpoint("192.168.1.42:port")).toBe(false)
  })
})

describe("hostPrefix", () => {
  it("keeps the host so only the port is left to type", () => {
    expect(hostPrefix("192.168.1.42:37123")).toBe("192.168.1.42")
    expect(hostPrefix("192.168.1.42")).toBe("192.168.1.42")
    expect(hostPrefix("[fe80::1]:37123")).toBe("[fe80::1]")
  })
})
