import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { Device } from "@/lib/wire"

const { captureScreenshot, show } = vi.hoisted(() => ({
  captureScreenshot: vi.fn(),
  show: vi.fn(),
}))

vi.mock("@/lib/daemon", () => ({
  captureScreenshot,
  copyImage: vi.fn(),
  savePng: vi.fn(),
  revealPath: vi.fn(),
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))
vi.mock("@/hooks/useNotifications", () => ({ useNotifications: () => ({ show }) }))

const { ScreenshotPane } = await import("@/components/ScreenshotPane")

const device: Device = {
  serial: "emulator-5554",
  state: "device",
  model: "Pixel",
  product: null,
  platform: "android",
} as Device

/** A 1x1 PNG, base64 — enough for `createImageBitmap` to be asked for one. */
const PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

describe("ScreenshotPane", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    captureScreenshot.mockResolvedValue({ png: PNG })
  })

  it("offers the Mac's four delays", () => {
    render(<ScreenshotPane device={device} />)
    const picker = screen.getByLabelText("Delay")
    expect([...picker.querySelectorAll("option")].map((o) => o.textContent)).toEqual([
      "No delay",
      "3s",
      "5s",
      "10s",
    ])
  })

  it("says nothing is written until you choose to", () => {
    render(<ScreenshotPane device={device} />)
    expect(screen.getByText(/nothing is written to disk until you choose to/u)).toBeDefined()
  })

  it("asks the daemon for the chosen delay", async () => {
    render(<ScreenshotPane device={device} />)
    fireEvent.change(screen.getByLabelText("Delay"), { target: { value: "5" } })
    fireEvent.click(screen.getByRole("button", { name: /Capture/u }))
    await waitFor(() => {
      expect(captureScreenshot).toHaveBeenCalledWith("emulator-5554", 5)
    })
  })

  it("reports a device that would not answer", async () => {
    captureScreenshot.mockRejectedValue(new Error("device offline"))
    render(<ScreenshotPane device={device} />)
    fireEvent.click(screen.getByRole("button", { name: /Capture/u }))
    await waitFor(() => {
      expect(show).toHaveBeenCalledWith(
        expect.objectContaining({ ok: false, message: expect.stringContaining("device offline") }),
      )
    })
  })

  it("asks for a device rather than offering a capture with none", () => {
    render(<ScreenshotPane device={null} />)
    expect(screen.queryByRole("button", { name: /Capture/u })).toBeNull()
  })
})
