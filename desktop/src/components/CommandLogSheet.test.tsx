import { fireEvent, render, screen, waitFor, within } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import type { CommandLogEntry } from "@/lib/wire"

const { commandLog, clearCommandLog } = vi.hoisted(() => ({
  commandLog: vi.fn(),
  clearCommandLog: vi.fn(),
}))

vi.mock("@/lib/daemon", () => ({
  commandLog,
  clearCommandLog,
  asDaemonError: (thrown: unknown) => ({ code: "unknown", message: String(thrown), detail: null }),
}))

const { CommandLogSheet } = await import("@/components/CommandLogSheet")

function entry(over: Partial<CommandLogEntry> = {}): CommandLogEntry {
  return {
    id: "a",
    at: Date.UTC(2026, 0, 2, 3, 4, 5),
    command: "adb -s emulator-5554 shell getprop",
    exitCode: 0,
    durationMs: 36,
    stdout: "[ro.product.model]: [sdk_gphone64_arm64]",
    stderr: "",
    ...over,
  }
}

describe("CommandLogSheet", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    commandLog.mockResolvedValue({ entries: [] })
    clearCommandLog.mockResolvedValue({ ok: true, message: "Command log cleared" })
  })

  it("says so when nothing has been recorded", async () => {
    render(<CommandLogSheet onDismiss={() => {}} />)
    expect(await screen.findByText("No commands yet")).toBeDefined()
    expect(screen.getByText("Commands you run appear here with their output.")).toBeDefined()
  })

  it("lists a recorded command with its exit status", async () => {
    commandLog.mockResolvedValue({ entries: [entry()] })
    render(<CommandLogSheet onDismiss={() => {}} />)
    expect(await screen.findByText("adb -s emulator-5554 shell getprop")).toBeDefined()
    expect(screen.getByText("exit 0 · 36ms")).toBeDefined()
  })

  it("shows the output only once a row is opened", async () => {
    commandLog.mockResolvedValue({ entries: [entry()] })
    render(<CommandLogSheet onDismiss={() => {}} />)

    const row = await screen.findByRole("button", { expanded: false })
    expect(screen.queryByText("[ro.product.model]: [sdk_gphone64_arm64]")).toBeNull()
    fireEvent.click(row)
    expect(screen.getByText("[ro.product.model]: [sdk_gphone64_arm64]")).toBeDefined()
  })

  it("says (no output) rather than leaving an opened row blank", async () => {
    commandLog.mockResolvedValue({ entries: [entry({ stdout: "", stderr: "" })] })
    render(<CommandLogSheet onDismiss={() => {}} />)
    fireEvent.click(await screen.findByRole("button", { expanded: false }))
    expect(screen.getByText("(no output)")).toBeDefined()
  })

  it("reports a daemon that would not answer", async () => {
    commandLog.mockRejectedValue(new Error("daemon is not running"))
    render(<CommandLogSheet onDismiss={() => {}} />)
    expect(await screen.findByText(/daemon is not running/u)).toBeDefined()
  })
})

describe("CommandLogSheet — clearing, refreshing and dismissing", () => {
  beforeEach(() => {
    vi.clearAllMocks()
    commandLog.mockResolvedValue({ entries: [] })
    clearCommandLog.mockResolvedValue({ ok: true, message: "Command log cleared" })
  })

  it("asks before clearing, and re-reads once it has", async () => {
    commandLog.mockResolvedValue({ entries: [entry()] })
    render(<CommandLogSheet onDismiss={() => {}} />)
    await screen.findByText("adb -s emulator-5554 shell getprop")

    fireEvent.click(screen.getByLabelText("Clear command log"))
    // A confirmationDialog on the Mac, so a dialog here — not a button that
    // arms itself, which is a different interaction to relearn.
    expect(screen.getByText("Clear the command log?")).toBeDefined()
    expect(clearCommandLog).not.toHaveBeenCalled()

    commandLog.mockResolvedValue({ entries: [] })
    fireEvent.click(within(screen.getByRole("alertdialog")).getByRole("button", { name: "Clear" }))
    await waitFor(() => {
      expect(clearCommandLog).toHaveBeenCalledOnce()
    })
    expect(await screen.findByText("No commands yet")).toBeDefined()
  })

  it("leaves the log alone when the clear is cancelled", async () => {
    commandLog.mockResolvedValue({ entries: [entry()] })
    render(<CommandLogSheet onDismiss={() => {}} />)
    await screen.findByText("adb -s emulator-5554 shell getprop")

    fireEvent.click(screen.getByLabelText("Clear command log"))
    // The dialog's backdrop also answers to "Cancel", so scope to the dialog.
    const dialog = within(screen.getByRole("alertdialog"))
    fireEvent.click(dialog.getByRole("button", { name: "Cancel" }))
    expect(clearCommandLog).not.toHaveBeenCalled()
    expect(screen.getByText("adb -s emulator-5554 shell getprop")).toBeDefined()
  })

  it("re-reads on Refresh", async () => {
    render(<CommandLogSheet onDismiss={() => {}} />)
    await screen.findByText("No commands yet")

    commandLog.mockResolvedValue({ entries: [entry({ command: "adb devices" })] })
    fireEvent.click(screen.getByLabelText("Refresh"))
    expect(await screen.findByText("adb devices")).toBeDefined()
  })

  it("closes on Close and on Escape", async () => {
    const onDismiss = vi.fn()
    render(<CommandLogSheet onDismiss={onDismiss} />)
    await screen.findByText("No commands yet")

    fireEvent.click(screen.getByRole("button", { name: "Close" }))
    expect(onDismiss).toHaveBeenCalledOnce()

    fireEvent.keyDown(document, { key: "Escape" })
    expect(onDismiss).toHaveBeenCalledTimes(2)
  })

  it("does not close on the Escape that dismisses the clear dialog", async () => {
    // Two overlays, one key: the dialog owns Escape while it is up, or
    // cancelling a clear would also shut the sheet behind it.
    const onDismiss = vi.fn()
    render(<CommandLogSheet onDismiss={onDismiss} />)
    await screen.findByText("No commands yet")

    fireEvent.click(screen.getByLabelText("Clear command log"))
    fireEvent.keyDown(document, { key: "Escape" })
    expect(onDismiss).not.toHaveBeenCalled()
  })

})
