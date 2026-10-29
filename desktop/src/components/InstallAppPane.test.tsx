import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { Device, InstallResponse, PackageDetails } from "@/lib/wire"

const { pickPackage, packageDetails, installPath, show, notifyIfBackgrounded } = vi.hoisted(
  () => ({
    pickPackage: vi.fn<() => Promise<string | null>>(),
    packageDetails: vi.fn<(path: string) => Promise<PackageDetails>>(),
    installPath: vi.fn<
      (serials: string[], path: string, opensApp: boolean) => Promise<InstallResponse>
    >(),
    show: vi.fn(),
    notifyIfBackgrounded: vi.fn(),
  }),
)

vi.mock("@/lib/daemon", () => ({
  pickPackage,
  packageDetails,
  installPath,
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))
vi.mock("@/hooks/useNotifications", () => ({
  useNotifications: () => ({ show, notifyIfBackgrounded }),
}))
vi.mock("@/hooks/useTargets", () => ({
  useTargets: () => ({ serials: ["emulator-5554"], runningOnAll: false }),
}))

const { InstallAppPane } = await import("@/components/InstallAppPane")
const { pendingStudioApk, listenForStudioApk } = await import("@/lib/apk-studio")

const device = { serial: "emulator-5554", label: "Pixel 9", state: "device" } as Device

const apiDemos: PackageDetails = {
  format: "apk",
  fileName: "ApiDemos.apk",
  fileSizeBytes: 4_700_000,
  label: "API Demos",
  packageName: "io.appium.android.apis",
  isDebuggable: true,
  version: "3.1.0  (18)",
  requires: "Android 4.2 (API 17) or later",
  targets: "Android 9 (API 28)",
  contents: null,
  nativeCode: "None — runs on any CPU",
  launcher: "ApiDemos",
  hasNoLauncher: false,
  signer: "Android Debug · v1, v2, v3 schemes",
  permissions: ["CAMERA", "INTERNET"],
  note: null,
}

function installed(fileName: string, extra: object = {}): InstallResponse {
  return { fileName, outcomes: [{ serial: "emulator-5554", ok: true, message: "Installed", ...extra }] }
}

async function choose() {
  act(() => {
    screen.getByRole("button", { name: "Choose File…" }).click()
  })
  await waitFor(() => {
    expect(installPath).toHaveBeenCalled()
  })
}

describe("InstallAppPane", () => {
  beforeEach(() => {
    localStorage.clear()
    for (const mock of [pickPackage, packageDetails, installPath, show, notifyIfBackgrounded]) {
      mock.mockReset()
    }
    packageDetails.mockResolvedValue(apiDemos)
  })

  it("installs with the box as it was last left, and remembers a change", async () => {
    localStorage.setItem("droidective.installOpensApp", "true")
    pickPackage.mockResolvedValue("/in/ApiDemos.apk")
    installPath.mockResolvedValue(installed("ApiDemos.apk", { opened: true }))
    render(<InstallAppPane device={device} onOpen={vi.fn()} />)

    const box = screen.getByRole<HTMLInputElement>("checkbox", { name: "Open after installing" })
    expect(box.checked).toBe(true)
    await choose()
    expect(installPath).toHaveBeenCalledWith(["emulator-5554"], "/in/ApiDemos.apk", true)
    await waitFor(() => {
      expect(show).toHaveBeenCalledWith({ ok: true, message: "Installed and opened ApiDemos.apk" })
    })

    fireEvent.click(box)
    expect(localStorage.getItem("droidective.installOpensApp")).toBe("false")
  })

  it("shows the package's details in its card", async () => {
    pickPackage.mockResolvedValue("/in/ApiDemos.apk")
    installPath.mockResolvedValue(installed("ApiDemos.apk"))
    render(<InstallAppPane device={device} onOpen={vi.fn()} />)
    await choose()

    expect(await screen.findByText("API Demos")).toBeTruthy()
    expect(screen.getByText("Debuggable")).toBeTruthy()
    expect(screen.getByText("io.appium.android.apis")).toBeTruthy()
    expect(screen.getByText("Android 4.2 (API 17) or later")).toBeTruthy()
    expect(screen.getByText("Android Debug · v1, v2, v3 schemes")).toBeTruthy()
    expect(screen.getByText("ApiDemos.apk · 4.7 MB")).toBeTruthy()
    // A line nobody could know is left out, not printed empty.
    expect(screen.queryByText("Contains")).toBeNull()
    expect(screen.getByRole("button", { name: "2 permissions" })).toBeTruthy()
  })

  it("says why the app couldn't be opened, without calling the install a failure", async () => {
    localStorage.setItem("droidective.installOpensApp", "true")
    pickPackage.mockResolvedValue("/in/lib.apk")
    installPath.mockResolvedValue(
      installed("lib.apk", { opened: false, openFailure: "Couldn't launch com.lib — no launcher." }),
    )
    render(<InstallAppPane device={device} onOpen={vi.fn()} />)
    await choose()

    await waitFor(() => {
      expect(show).toHaveBeenCalledWith({ ok: true, message: "Installed lib.apk" })
    })
    expect(show).toHaveBeenCalledWith({
      ok: false,
      message: "Installed lib.apk. Couldn't launch com.lib — no launcher.",
    })
  })

  it("hands a plain APK to APK Studio, and offers no such thing for a bundle", async () => {
    const onOpen = vi.fn()
    pickPackage.mockResolvedValue("/in/ApiDemos.apk")
    installPath.mockResolvedValue(installed("ApiDemos.apk"))
    const { unmount } = render(<InstallAppPane device={device} onOpen={onOpen} />)
    await choose()

    act(() => {
      screen.getByRole("button", { name: "Open in APK Studio" }).click()
    })
    expect(onOpen).toHaveBeenCalledWith("apk-studio")
    expect(pendingStudioApk()).toBe("/in/ApiDemos.apk")
    listenForStudioApk(() => {})()
    unmount()

    pickPackage.mockResolvedValue("/in/Bundle.xapk")
    installPath.mockResolvedValue(installed("Bundle.xapk"))
    render(<InstallAppPane device={device} onOpen={onOpen} />)
    await choose()
    expect(screen.queryByRole("button", { name: "Open in APK Studio" })).toBeNull()
  })

  it("does nothing at all for a dismissed picker", async () => {
    pickPackage.mockResolvedValue(null)
    render(<InstallAppPane device={device} onOpen={vi.fn()} />)
    act(() => {
      screen.getByRole("button", { name: "Choose File…" }).click()
    })
    await waitFor(() => {
      expect(pickPackage).toHaveBeenCalled()
    })
    expect(installPath).not.toHaveBeenCalled()
    expect(show).not.toHaveBeenCalled()
  })
})
