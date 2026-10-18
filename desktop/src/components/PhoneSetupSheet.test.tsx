import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { PhoneSetupSheet } from "@/components/PhoneSetupSheet"
import type { PhoneSetupStatus } from "@/lib/wire"

vi.mock("@/lib/daemon", () => ({
  phoneSetupStatus: vi.fn(),
  setUpPhone: vi.fn(),
  asDaemonError: (thrown: unknown) => ({
    message: thrown instanceof Error ? thrown.message : String(thrown),
  }),
}))

const fresh: PhoneSetupStatus = {
  appInstalled: true,
  appVersion: "0.1.0",
  grantedPermissions: [],
  missingPermissions: ["android.permission.WRITE_SECURE_SETTINGS", "android.permission.DUMP"],
  shizukuInstalled: true,
  shizukuRunning: false,
  needsSetup: true,
}

const done: PhoneSetupStatus = {
  ...fresh,
  grantedPermissions: fresh.missingPermissions,
  missingPermissions: [],
  shizukuRunning: true,
  needsSetup: false,
}

function sheet(onStatus = vi.fn()) {
  render(<PhoneSetupSheet serial="S1" name="Pixel 8" onStatus={onStatus} onDismiss={vi.fn()} />)
  return onStatus
}

/**
 * The sheet only shows the daemon's answers, so what is worth defending is the
 * flow: read on open (not marked background — it is something the user did),
 * one button that is live only when there is something to do, and adb's
 * reason inline when a step fails.
 */
describe("PhoneSetupSheet", () => {
  beforeEach(async () => {
    const daemon = await import("@/lib/daemon")
    vi.mocked(daemon.phoneSetupStatus).mockReset()
    vi.mocked(daemon.setUpPhone).mockReset()
  })

  it("reads the phone on open, as a user action, and reports what it read", async () => {
    const { phoneSetupStatus } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(fresh)
    const onStatus = sheet()

    await screen.findByText("Missing WRITE_SECURE_SETTINGS and DUMP.")
    expect(phoneSetupStatus).toHaveBeenCalledWith("S1", false)
    expect(onStatus).toHaveBeenCalledWith(fresh)
    expect(screen.getByRole("button", { name: "Set Up" })).toHaveProperty("disabled", false)
  })

  it("sets up, then shows the rows the phone reports afterwards", async () => {
    const { phoneSetupStatus, setUpPhone } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(fresh)
    vi.mocked(setUpPhone).mockResolvedValue({ status: done, failure: null })
    const onStatus = sheet()

    await screen.findByText("Installed, not running.")
    fireEvent.click(screen.getByRole("button", { name: "Set Up" }))

    await screen.findByText("All set.")
    expect(setUpPhone).toHaveBeenCalledWith("S1")
    expect(onStatus).toHaveBeenLastCalledWith(done)
    expect(screen.getByText("Running")).toBeDefined()
    expect(screen.getByRole("button", { name: "Set Up" })).toHaveProperty("disabled", true)
  })

  it("shows the failing step's reason inline, with what did land", async () => {
    const { phoneSetupStatus, setUpPhone } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(fresh)
    const partial = { ...done, shizukuRunning: false, needsSetup: true }
    vi.mocked(setUpPhone).mockResolvedValue({
      status: partial,
      failure: "Shizuku didn't start: fatal: can't start server",
    })
    sheet()

    await screen.findByText("Installed, not running.")
    fireEvent.click(screen.getByRole("button", { name: "Set Up" }))

    await screen.findByText("Shizuku didn't start: fatal: can't start server")
    expect(screen.getByText("WRITE_SECURE_SETTINGS and DUMP")).toBeDefined()
  })

  it("offers nothing to press on a phone that is already set up", async () => {
    const { phoneSetupStatus } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(done)
    sheet()

    await screen.findByText("Nothing to do — this phone is set up.")
    expect(screen.getByRole("button", { name: "Set Up" })).toHaveProperty("disabled", true)
  })

  it("says the phone could not be read rather than that nothing is installed", async () => {
    const { phoneSetupStatus } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockRejectedValue(new Error("Device is offline."))
    sheet()

    await screen.findByText("Device is offline.")
    await waitFor(() => {
      expect(screen.getAllByText("Couldn't read the phone.")).toHaveLength(3)
    })
    expect(screen.queryByText(/Install Droidective/u)).toBeNull()
  })
})
