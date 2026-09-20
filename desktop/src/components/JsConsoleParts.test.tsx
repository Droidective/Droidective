import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import type { CdpTarget } from "@/lib/metro"

vi.mock("@/lib/daemon", () => ({
  listApps: vi.fn(() => Promise.resolve({ apps: [] })),
  foregroundApp: vi.fn(() => Promise.resolve({ packageId: null })),
  controlApp: vi.fn(() => Promise.resolve({ ok: true, message: "" })),
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))

const { Bar } = await import("@/components/JsConsoleParts")

const target: CdpTarget = {
  id: "t1",
  title: "Demo",
  appId: "com.example.demo",
  detail: "Hermes",
  deviceName: "Pixel",
  vm: "Hermes",
  webSocketDebuggerUrl: "ws://localhost:8081/inspector/debug",
  logicalDeviceId: null,
}

/** A console in whatever state the test needs, with nothing else wired up. */
function fakeConsole(overrides: Record<string, unknown> = {}) {
  return {
    rows: [],
    targets: [target],
    target,
    connection: "connected",
    problem: null,
    connect: vi.fn(),
    refresh: vi.fn(),
    clear: vi.fn(),
    evaluate: vi.fn(),
    expand: vi.fn(),
    reloadJs: vi.fn(),
    ...overrides,
  } as unknown as Parameters<typeof Bar>[0]["console"]
}

function bar(overrides: Record<string, unknown> = {}, serial: string | null = "abc") {
  return (
    <Bar
      console={fakeConsole(overrides)}
      port={8081}
      onPort={vi.fn()}
      serial={serial}
      onReload={vi.fn()}
      onReport={vi.fn()}
      onReverse={vi.fn()}
    />
  )
}

describe("the JS Console's connection bar", () => {
  it("says the Metro port varies per app, which nothing else on the screen does", () => {
    render(bar())
    const field = screen.getByLabelText("Metro port")
    expect(field.getAttribute("title")).toBe("Metro dev-server port — varies per app")
    expect(field.getAttribute("placeholder")).toBe("8081")
  })

  it("offers Reload JS while connected", () => {
    render(bar())
    expect(screen.getByRole("button", { name: /Reload JS/u })).toBeTruthy()
  })

  it("hides Reload JS when nothing is connected", () => {
    // The Mac's rule: there is no runtime to ask, so the button would only be
    // able to fail.
    render(bar({ connection: "idle", target: null }))
    expect(screen.queryByRole("button", { name: /Reload JS/u })).toBeNull()
  })

  it("carries the Mac's Reload JS tooltip, with Ctrl for its one Mac key", () => {
    // The standing shortcut exception, and the only difference from the Mac's
    // sentence: RN DevTools binds Ctrl+R on the platforms this build runs on.
    render(bar())
    expect(screen.getByRole("button", { name: /Reload JS/u }).getAttribute("title")).toBe(
      "Reload the JS bundle — what Ctrl+R in React Native DevTools does",
    )
  })

  it("offers Restart app whenever a device is selected", () => {
    // Not gated on the connection: restarting is how you get a console back
    // when the app has gone away, which is exactly when it is disconnected.
    render(bar({ connection: "idle", target: null }))
    expect(screen.getByRole("button", { name: /Restart app/u })).toBeTruthy()
  })

  it("has no Restart app without a device to restart on", () => {
    render(bar({}, null))
    expect(screen.queryByRole("button", { name: /Restart app/u })).toBeNull()
  })

  it("keeps the restart variants behind the chevron, as the Mac's split button does", () => {
    render(bar())
    expect(screen.queryByText("Clear cache and restart")).toBeNull()
    expect(screen.getByRole("button", { name: "Restart options" })).toBeTruthy()
  })
})
