import { describe, expect, it } from "vitest"
import { isMacHost, shortcutLabel } from "@/lib/platform"

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
