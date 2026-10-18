import { fireEvent, render, screen } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { Device, FeatureSummary } from "@/lib/wire"

const { setEnabled, connect, apply } = vi.hoisted(() => ({
  setEnabled: vi.fn(),
  connect: vi.fn(),
  apply: vi.fn(),
}))

vi.mock("@/hooks/useWifi", () => ({
  useWifi: () => ({
    data: {
      status: {
        enabled: true,
        connected: true,
        ssid: "Office",
        ipAddress: null,
        linkSpeed: null,
        frequency: null,
        signal: null,
      },
      networks: [],
      hasRootShell: false,
    },
    error: null,
    loaded: true,
    busy: false,
    refresh: vi.fn(),
    setEnabled,
    connect,
    copyPassword: vi.fn(),
  }),
}))

vi.mock("@/hooks/useDeviceSettings", () => ({
  useDeveloperSettings: () => ({
    settings: {
      toggles: [{ id: "show-touches", title: "Show taps", detail: "", on: false }],
      scales: [],
      scaleChoices: [0, 1],
    },
    error: null,
    refreshing: false,
    refresh: vi.fn(),
    apply,
  }),
  withToggle: (current: unknown) => current,
  withScale: (current: unknown) => current,
}))

const { RemoteLinkProvider } = await import("@/hooks/useRemoteLink")
const { WifiPane } = await import("@/components/WifiPane")
const { DevSettingsPane } = await import("@/components/DevSettingsPane")

const WIFI_WARNING = "Turning Wi-Fi off or joining another network can take it off your tailnet."
const DEV_WARNING =
  "Developer settings change how the phone runs, and are applied on the phone itself."

const features = [
  { id: "wifi", remoteLinkWarning: WIFI_WARNING },
  { id: "dev-settings", remoteLinkWarning: DEV_WARNING },
  { id: "screenshot", remoteLinkWarning: null },
] as FeatureSummary[]

function phone(serial: string, label: string): Device {
  return {
    serial,
    state: "device",
    model: "Pixel 7",
    product: null,
    transportId: null,
    label,
    isWireless: serial.includes(":"),
    platform: "android",
  }
}

const remote = phone("100.101.102.103:5555", "Pixel 7 (5555)")
const cabled = phone("R58M123ABC", "Pixel 7 (3ABC)")

function inWindow(pane: React.ReactNode) {
  render(
    <RemoteLinkProvider features={features} devices={[remote, cabled]}>
      {pane}
    </RemoteLinkProvider>,
  )
}

beforeEach(() => {
  setEnabled.mockClear()
  connect.mockClear()
  apply.mockClear()
})

/** On a phone reached over Tailscale, Wi-Fi asks before it can cut the link. */
describe("Wi-Fi on a tailnet phone", () => {
  it("asks before turning the radio off, naming the phone and the risk", () => {
    inWindow(<WifiPane device={remote} />)
    const radio = screen.getByRole("switch", { name: "Wi-Fi" })
    fireEvent.click(radio)

    expect(setEnabled).not.toHaveBeenCalled()
    const dialog = screen.getByRole("alertdialog", {
      name: "Pixel 7 (5555) is connected over Tailscale",
    })
    expect(dialog.textContent).toContain(
      `${WIFI_WARNING} If the link drops, reconnecting needs the phone in hand.`,
    )

    fireEvent.click(screen.getByRole("button", { name: "Turn Wi-Fi Off" }))
    expect(setEnabled).toHaveBeenCalledWith(false)
    expect(screen.queryByRole("alertdialog")).toBeNull()
  })

  it("leaves the radio where it was on Cancel", () => {
    inWindow(<WifiPane device={remote} />)
    fireEvent.click(screen.getByRole("switch", { name: "Wi-Fi" }))
    fireEvent.click(screen.getAllByRole("button", { name: "Cancel" })[1] as HTMLElement)

    expect(setEnabled).not.toHaveBeenCalled()
    expect(screen.queryByRole("alertdialog")).toBeNull()
    expect(screen.getByRole("switch", { name: "Wi-Fi" }).getAttribute("aria-checked")).toBe("true")
  })

  it("asks before joining another network too", () => {
    inWindow(<WifiPane device={remote} />)
    fireEvent.change(screen.getByPlaceholderText("SSID"), { target: { value: "Guest" } })
    fireEvent.click(screen.getByRole("button", { name: "Connect" }))
    expect(connect).not.toHaveBeenCalled()

    fireEvent.click(
      screen.getAllByRole("button", { name: "Connect" }).at(-1) as HTMLElement,
    )
    expect(connect).toHaveBeenCalledWith("Guest", "wpa2", "")
  })

  it("does not ask on a cabled phone", () => {
    inWindow(<WifiPane device={cabled} />)
    fireEvent.click(screen.getByRole("switch", { name: "Wi-Fi" }))
    expect(screen.queryByRole("alertdialog")).toBeNull()
    expect(setEnabled).toHaveBeenCalledWith(false)
  })

  it("does not ask outside a window that knows the registry", () => {
    render(<WifiPane device={remote} />)
    fireEvent.click(screen.getByRole("switch", { name: "Wi-Fi" }))
    expect(setEnabled).toHaveBeenCalledWith(false)
  })
})

describe("Developer Settings on a tailnet phone", () => {
  it("asks before a change, and a cancelled one leaves the row alone", () => {
    inWindow(<DevSettingsPane device={remote} />)
    const row = screen.getByRole("switch", { name: "Show taps" })
    fireEvent.click(row)
    expect(apply).not.toHaveBeenCalled()
    expect(screen.getByRole("alertdialog").textContent).toContain(DEV_WARNING)

    fireEvent.click(screen.getAllByRole("button", { name: "Cancel" })[1] as HTMLElement)
    expect(apply).not.toHaveBeenCalled()
    expect(screen.getByRole("switch", { name: "Show taps" }).getAttribute("aria-checked")).toBe(
      "false",
    )

    fireEvent.click(screen.getByRole("switch", { name: "Show taps" }))
    fireEvent.click(screen.getByRole("button", { name: "Change Setting" }))
    expect(apply).toHaveBeenCalledOnce()
  })

  it("applies at once on a cabled phone", () => {
    inWindow(<DevSettingsPane device={cabled} />)
    fireEvent.click(screen.getByRole("switch", { name: "Show taps" }))
    expect(screen.queryByRole("alertdialog")).toBeNull()
    expect(apply).toHaveBeenCalledOnce()
  })
})
