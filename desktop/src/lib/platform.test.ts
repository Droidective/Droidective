import { describe, expect, it } from "vitest"
import { isLinuxHost, isMacHost, shortcutLabel } from "@/lib/platform"

describe("shortcutLabel", () => {
  it("uses the accelerator the host actually has", () => {
    expect(shortcutLabel("w", true)).toBe("⌘W")
    expect(shortcutLabel("w", false)).toBe("Ctrl+W")
  })
})

describe("isMacHost", () => {
  it("recognises the webview this app is developed in", () => {
    expect(isMacHost("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15")).toBe(
      true,
    )
  })

  it("recognises the webviews it ships on", () => {
    expect(isMacHost("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120 Edg/120")).toBe(false)
    expect(isMacHost("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/605.1.15")).toBe(false)
  })
})

describe("isLinuxHost", () => {
  it("recognises the WebKitGTK user agent the Linux build runs under", () => {
    expect(
      isLinuxHost("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"),
    ).toBe(true)
  })

  it("is false on the other two platforms", () => {
    expect(isLinuxHost("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15")).toBe(false)
    expect(isLinuxHost("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")).toBe(false)
  })

  /**
   * The trap this exists to avoid: Android's user agent contains "Linux", and
   * this app talks *to* Android. A webview that ever reported one would turn
   * window translucency off for the wrong reason.
   */
  it("does not mistake an Android user agent for a Linux desktop", () => {
    expect(isLinuxHost("Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36")).toBe(false)
  })
})
