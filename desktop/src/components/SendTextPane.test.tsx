import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { Device } from "@/lib/wire"

const { snippets, writeSnippet, expandSnippet, runAction, show } = vi.hoisted(() => ({
  snippets: vi.fn(),
  writeSnippet: vi.fn(),
  expandSnippet: vi.fn(),
  runAction: vi.fn(),
  show: vi.fn(),
}))

vi.mock("@/lib/daemon", () => ({
  snippets,
  writeSnippet,
  expandSnippet,
  runAction,
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))
vi.mock("@/hooks/useNotifications", () => ({ useNotifications: () => ({ show }) }))

const { SendTextPane } = await import("@/components/SendTextPane")

const device = { serial: "emulator-5554", state: "device", platform: "android" } as Device

const login = { name: "Login", text: "me@example.com", uses: 3, lastUsedAt: 200 }
const metro = { name: "Metro", text: "http://{ip}:8081", uses: 1, lastUsedAt: 300 }

describe("SendTextPane", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    snippets.mockResolvedValue([login, metro])
    writeSnippet.mockResolvedValue([login, metro])
    expandSnippet.mockResolvedValue({ text: "http://192.168.1.5:8081", hostIp: "192.168.1.5" })
    runAction.mockResolvedValue({ ok: true, message: "Text sent" })
  })

  it("asks for a device rather than offering to send with none", () => {
    render(<SendTextPane device={null} />)
    expect(screen.queryByRole("button", { name: /Send/u })).toBeNull()
  })

  it("lists the snippets most recently used first", async () => {
    render(<SendTextPane device={device} />)
    await screen.findByText("Metro")
    const names = screen.getAllByText(/^(Login|Metro)$/u).map((node) => node.textContent)
    expect(names).toEqual(["Metro", "Login"])
  })

  it("sends what is typed", async () => {
    render(<SendTextPane device={device} />)
    fireEvent.change(screen.getByPlaceholderText("Type or paste text to send…"), {
      target: { value: "hello" },
    })
    fireEvent.click(screen.getByRole("button", { name: /Send/u }))
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledWith({
        featureId: "send-text",
        serial: "emulator-5554",
        fields: { text: "hello" },
      })
    })
  })

  it("sends on Return, as the Mac does", async () => {
    render(<SendTextPane device={device} />)
    const field = screen.getByPlaceholderText("Type or paste text to send…")
    fireEvent.change(field, { target: { value: "hi" } })
    fireEvent.keyDown(field, { key: "Enter" })
    await waitFor(() => {
      expect(runAction).toHaveBeenCalledOnce()
    })
  })

  it("inserts a snippet with its live values filled in, and counts the use", async () => {
    render(<SendTextPane device={device} />)
    fireEvent.click(await screen.findByText("Metro"))
    await waitFor(() => {
      expect(expandSnippet).toHaveBeenCalledWith("http://{ip}:8081")
    })
    // The expanded text, not the placeholder — the whole point of the chip.
    expect(
      (screen.getByPlaceholderText("Type or paste text to send…") as HTMLInputElement).value,
    ).toBe("http://192.168.1.5:8081")
    await waitFor(() => {
      expect(writeSnippet).toHaveBeenCalledWith({ op: "use", name: "Metro" })
    })
  })

  it("filters by the text as well as the name", async () => {
    render(<SendTextPane device={device} />)
    await screen.findByText("Metro")
    fireEvent.change(screen.getByPlaceholderText("Search snippets…"), {
      target: { value: "example.com" },
    })
    expect(screen.getByText("Login")).toBeDefined()
    expect(screen.queryByText("Metro")).toBeNull()
  })

  it("says so when a search matches nothing", async () => {
    render(<SendTextPane device={device} />)
    await screen.findByText("Metro")
    fireEvent.change(screen.getByPlaceholderText("Search snippets…"), {
      target: { value: "zzz" },
    })
    expect(screen.getByText(/No snippets match/u)).toBeDefined()
  })

  it("removes one", async () => {
    render(<SendTextPane device={device} />)
    fireEvent.click(await screen.findByLabelText("Remove Login"))
    await waitFor(() => {
      expect(writeSnippet).toHaveBeenCalledWith({ op: "remove", name: "Login" })
    })
  })

  it("invites the first one when there are none", async () => {
    snippets.mockResolvedValue([])
    render(<SendTextPane device={device} />)
    expect(await screen.findByText(/No snippets yet/u)).toBeDefined()
    // No search field over an empty list — it would be a control with nothing
    // to do, which is what the Mac avoids by hiding it.
    expect(screen.queryByPlaceholderText("Search snippets…")).toBeNull()
  })
})
