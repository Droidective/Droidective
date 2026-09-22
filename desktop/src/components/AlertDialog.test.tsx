import { fireEvent, render, screen, within } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { AlertDialog } from "@/components/AlertDialog"

/**
 * An alert states something; it does not ask. The one button is the default
 * action, which is the difference from `ConfirmDialog` worth testing.
 */
describe("AlertDialog", () => {
  const props = { title: "Device disconnected", onDismiss: vi.fn() }

  it("offers one way out, and it says OK", () => {
    render(<AlertDialog {...props} />)
    const dialog = within(screen.getByRole("alertdialog"))
    expect(dialog.getByRole("button", { name: "OK" })).toBeDefined()
    expect(dialog.queryByRole("button", { name: "Cancel" })).toBeNull()
  })

  it("dismisses on Return as well as Escape", () => {
    // OK is the default action on the Mac. The confirm dialog deliberately does
    // not do this — there the primary button is destructive.
    const onDismiss = vi.fn()
    render(<AlertDialog {...props} onDismiss={onDismiss} />)
    fireEvent.keyDown(document, { key: "Enter" })
    fireEvent.keyDown(document, { key: "Escape" })
    expect(onDismiss).toHaveBeenCalledTimes(2)
  })

  it("shows the explanatory line when there is one", () => {
    render(<AlertDialog {...props} message="Reactotron keeps listening on :9090." />)
    expect(screen.getByText("Reactotron keeps listening on :9090.")).toBeDefined()
  })
})
