import { render, screen, within } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { ConfirmDialog } from "@/components/ConfirmDialog"

/**
 * The safe choice's wording.
 *
 * Most dialogs have nothing to disambiguate and say "Cancel". The ones the Mac
 * names after what *continues* need the same word here, or the port asks a
 * different question from the app it is copying.
 */
describe("ConfirmDialog", () => {
  const props = {
    title: "Delete this?",
    confirmLabel: "Delete",
    onConfirm: vi.fn(),
    onCancel: vi.fn(),
  }

  it("says Cancel when there is nothing to disambiguate", () => {
    render(<ConfirmDialog {...props} />)
    expect(within(screen.getByRole("alertdialog")).getByRole("button", { name: "Cancel" }))
      .toBeDefined()
  })

  it("says what carries on when the Mac names it", () => {
    // "Cancel" in a dialog about stopping a recording reads as cancelling the
    // recording — the opposite of what the button does.
    render(<ConfirmDialog {...props} cancelLabel="Keep recording" />)
    const dialog = within(screen.getByRole("alertdialog"))
    expect(dialog.getByRole("button", { name: "Keep recording" })).toBeDefined()
    expect(dialog.queryByRole("button", { name: "Cancel" })).toBeNull()
  })

  it("labels the backdrop with the same word, so it is not a second answer", () => {
    // The backdrop dismisses too, and a screen reader announcing "Cancel" over
    // a dialog whose button says "Keep recording" describes two choices where
    // there is one.
    render(<ConfirmDialog {...props} cancelLabel="Keep recording" />)
    expect(screen.getAllByRole("button", { name: "Keep recording" })).toHaveLength(2)
  })
})
