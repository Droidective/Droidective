import { act, renderHook } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

import { useApiShortcuts } from "@/hooks/useApiShortcuts"

const onSend = vi.fn()
const onSave = vi.fn()

beforeEach(() => {
  onSend.mockClear()
  onSave.mockClear()
})

function press(key: string, extra: Partial<KeyboardEventInit> = {}) {
  act(() => {
    globalThis.dispatchEvent(new KeyboardEvent("keydown", { key, ctrlKey: true, ...extra }))
  })
}

function mount(over: { canSend?: boolean; canSave?: boolean } = {}) {
  renderHook(() =>
    useApiShortcuts({
      onSend,
      onSave,
      canSend: over.canSend ?? true,
      canSave: over.canSave ?? true,
    }),
  )
}

describe("the request bar's chords", () => {
  it("sends on the accelerator and Enter", () => {
    // The bar has promised this in a tooltip since it shipped; nothing bound it.
    mount()
    press("Enter")
    expect(onSend).toHaveBeenCalledOnce()
  })

  it("saves on the accelerator and S", () => {
    mount()
    press("s")
    expect(onSave).toHaveBeenCalledOnce()
  })

  it("does not send a request that is not ready", () => {
    mount({ canSend: false })
    press("Enter")
    expect(onSend).not.toHaveBeenCalled()
  })

  it("ignores a bare Enter, which the URL field already owns", () => {
    mount()
    act(() => {
      globalThis.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }))
    })
    expect(onSend).not.toHaveBeenCalled()
  })

  it("ignores the chord with another modifier held", () => {
    // Shift+Ctrl+Enter is not this, and claiming it would shadow whatever is.
    mount()
    press("Enter", { shiftKey: true })
    press("s", { altKey: true })
    expect(onSend).not.toHaveBeenCalled()
    expect(onSave).not.toHaveBeenCalled()
  })
})
