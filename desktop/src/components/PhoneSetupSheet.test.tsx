import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { PhoneSetupSheet } from "@/components/PhoneSetupSheet"
import type { PhoneSetupProgress, PhoneSetupStatus, StreamUpdate } from "@/lib/wire"

vi.mock("@/lib/daemon", () => ({
  phoneSetupStatus: vi.fn(),
  watchPhoneSetup: vi.fn(),
  asDaemonError: (thrown: unknown) => ({
    message: thrown instanceof Error ? thrown.message : String(thrown),
  }),
}))

const fresh: PhoneSetupStatus = {
  appInstalled: true,
  appVersion: "0.1.1",
  sdk: 36,
  grantedPermissions: [],
  missingPermissions: ["android.permission.WRITE_SECURE_SETTINGS", "android.permission.DUMP"],
  shizukuInstalled: true,
  shizukuRunning: false,
  needsSetup: true,
  latestVersion: "0.1.1",
  latestProblem: null,
  step: "none",
  hasWork: true,
  offer: { kind: "setUp", menuTitle: "Set Up Droidective on This Phone…", from: null, to: null },
}

const done: PhoneSetupStatus = {
  ...fresh,
  grantedPermissions: fresh.missingPermissions,
  missingPermissions: [],
  shizukuRunning: true,
  needsSetup: false,
  hasWork: false,
  offer: null,
}

const absent: PhoneSetupStatus = {
  ...fresh,
  appInstalled: false,
  appVersion: null,
  missingPermissions: [],
  needsSetup: false,
  step: "install",
  offer: { kind: "install", menuTitle: "Install Droidective on This Phone…", from: null, to: null },
}

/** `done` as the stream carries it: Swift leaves its nil keys out. */
const streamedDone: PhoneSetupProgress["status"] = {
  appInstalled: true,
  appVersion: "0.1.1",
  sdk: 36,
  grantedPermissions: done.grantedPermissions,
  missingPermissions: [],
  shizukuInstalled: true,
  shizukuRunning: true,
  needsSetup: false,
  latestVersion: "0.1.1",
  step: "none",
  hasWork: false,
}

function sheet(onOffer = vi.fn()) {
  render(<PhoneSetupSheet serial="S1" name="Pixel 8" onOffer={onOffer} onDismiss={vi.fn()} />)
  return onOffer
}

/**
 * Plays a run's events into the sheet the way the daemon sends them. `hold`
 * leaves the run open until `release`, to look at it before the outcome.
 */
async function script(events: StreamUpdate<PhoneSetupProgress>[], hold = false) {
  const { watchPhoneSetup } = await import("@/lib/daemon")
  const stop = vi.fn(() => Promise.resolve())
  let deliver: ((update: StreamUpdate<PhoneSetupProgress>) => void) | null = null
  vi.mocked(watchPhoneSetup).mockImplementation((_serial, onUpdate) => {
    deliver = onUpdate
    if (!hold) for (const event of events) onUpdate(event)
    return Promise.resolve({ id: 1, stop })
  })
  return {
    stop,
    release: () => {
      for (const event of events) deliver?.(event)
    },
  }
}

/**
 * The sheet only shows the daemon's answers, so what is worth defending is the
 * flow: read on open (not marked background — it is something the user did),
 * one button named for what it does first and live only when there is
 * something to do, each stage as it arrives, and adb's reason inline when a
 * step fails.
 */
beforeEach(async () => {
  const daemon = await import("@/lib/daemon")
  vi.mocked(daemon.phoneSetupStatus).mockReset()
  vi.mocked(daemon.watchPhoneSetup).mockReset()
})

describe("PhoneSetupSheet reading the phone", () => {
  it("reads the phone on open, as a user action, and reports what to offer", async () => {
    const { phoneSetupStatus } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(fresh)
    const onOffer = sheet()

    await screen.findByText("Missing WRITE_SECURE_SETTINGS and DUMP.")
    expect(phoneSetupStatus).toHaveBeenCalledWith("S1", false)
    expect(onOffer).toHaveBeenCalledWith(fresh.offer)
    expect(screen.getByRole("button", { name: "Set Up" })).toHaveProperty("disabled", false)
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
    expect(screen.queryByText(/Not installed/u)).toBeNull()
  })
})

describe("PhoneSetupSheet running", () => {
  it("installs a missing app, naming each stage, then shows what the phone reports", async () => {
    const { phoneSetupStatus, watchPhoneSetup } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(absent)
    const run = await script(
      [
        { event: "subscribed" },
        { event: "batch", items: [{ stage: "Downloading 0.1.1… 42%" }] },
        { event: "batch", items: [{ done: true, status: streamedDone }] },
        { event: "ended", reason: "completed" },
      ],
      true,
    )
    const onOffer = sheet()

    await screen.findByText("Not installed. Install downloads 0.1.1 from GitHub.")
    fireEvent.click(screen.getByRole("button", { name: "Install" }))
    expect(watchPhoneSetup).toHaveBeenCalledWith("S1", expect.any(Function))
    await screen.findByText("Setting up…")

    run.release()
    await screen.findByText("All set.")
    expect(onOffer).toHaveBeenLastCalledWith(null)
    expect(screen.getByText("Droidective for Android 0.1.1")).toBeDefined()
    expect(screen.getByText("Running")).toBeDefined()
    expect(screen.getByRole("button", { name: "Set Up" })).toHaveProperty("disabled", true)
    expect(run.stop).toHaveBeenCalled()
  })

  it("shows the stage the run is at while it runs", async () => {
    const { phoneSetupStatus } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(absent)
    await script([{ event: "batch", items: [{ stage: "Checking the signature…" }] }])
    sheet()

    await screen.findByText("Not installed. Install downloads 0.1.1 from GitHub.")
    fireEvent.click(screen.getByRole("button", { name: "Install" }))
    await screen.findByText("Checking the signature…")
  })

  it("shows the failing step's reason inline, with what did land", async () => {
    const { phoneSetupStatus } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(fresh)
    await script([
      {
        event: "batch",
        items: [
          {
            done: true,
            status: { ...streamedDone, shizukuRunning: false, needsSetup: true, hasWork: true },
            failure: "Shizuku didn't start: fatal: can't start server",
          },
        ],
      },
      { event: "ended", reason: "completed" },
    ])
    sheet()

    await screen.findByText("Installed, not running.")
    fireEvent.click(screen.getByRole("button", { name: "Set Up" }))

    await screen.findByText("Shizuku didn't start: fatal: can't start server")
    expect(screen.getByText("WRITE_SECURE_SETTINGS and DUMP")).toBeDefined()
  })

  it("says so when the run ends without an outcome", async () => {
    const { phoneSetupStatus } = await import("@/lib/daemon")
    vi.mocked(phoneSetupStatus).mockResolvedValue(fresh)
    await script([{ event: "ended", reason: "device_disconnected" }])
    sheet()

    await screen.findByText("Installed, not running.")
    fireEvent.click(screen.getByRole("button", { name: "Set Up" }))
    await screen.findByText("The set-up stopped before it finished.")
  })
})
