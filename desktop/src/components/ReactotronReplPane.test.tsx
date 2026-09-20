import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { ReactotronReplPane } from "@/components/ReactotronReplPane"
import type { ReactotronReplSession } from "@/hooks/useReactotronRepl"

function session(over: Partial<ReactotronReplSession> = {}): ReactotronReplSession {
  return {
    names: [],
    result: null,
    notice: null,
    refresh: vi.fn(),
    run: vi.fn(),
    ...over,
  }
}

describe("ReactotronReplPane", () => {
  it("lists what is in scope, because nothing else says", () => {
    // An expression naming something the app never registered comes back
    // undefined, which looks identical to an expression that went wrong.
    render(<ReactotronReplPane session={session({ names: ["store", "api"] })} />)
    expect(screen.getByText("Available: store, api")).toBeDefined()
  })

  it("says nothing about scope when the app registered nothing", () => {
    render(<ReactotronReplPane session={session()} />)
    expect(screen.queryByText(/Available:/u)).toBeNull()
  })

  it("will not evaluate an empty box", () => {
    render(<ReactotronReplPane session={session()} />)
    expect(screen.getByRole("button", { name: "Evaluate" }).hasAttribute("disabled")).toBe(true)
  })

  it("evaluates what was typed", () => {
    const run = vi.fn()
    render(<ReactotronReplPane session={session({ run })} />)
    fireEvent.change(screen.getByLabelText("Expression"), {
      target: { value: "store.getState()" },
    })
    fireEvent.click(screen.getByRole("button", { name: "Evaluate" }))
    expect(run).toHaveBeenCalledWith("store.getState()")
  })

  it("shows undefined as a result rather than an empty panel", () => {
    // An expression that returned nothing still ran.
    render(<ReactotronReplPane session={session({ result: "undefined" })} />)
    expect(screen.getByText("Result")).toBeDefined()
    expect(screen.getByText("undefined")).toBeDefined()
  })

  it("has no Result heading before anything has been run", () => {
    render(<ReactotronReplPane session={session()} />)
    expect(screen.queryByText("Result")).toBeNull()
  })

  it("offers Refresh with the Mac's tooltip", () => {
    const refresh = vi.fn()
    render(<ReactotronReplPane session={session({ refresh })} />)
    const button = screen.getByRole("button", { name: "Refresh available values" })
    expect(button.title).toBe("Refresh available values")
    fireEvent.click(button)
    expect(refresh).toHaveBeenCalledOnce()
  })

  it("surfaces a notice, which is where a refusal appears", () => {
    render(<ReactotronReplPane session={session({ notice: "No app is connected." })} />)
    expect(screen.getByText("No app is connected.")).toBeDefined()
  })
})
