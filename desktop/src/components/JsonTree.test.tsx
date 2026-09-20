import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

vi.mock("@/lib/daemon", () => ({ copyText: vi.fn(() => Promise.resolve()) }))

const { JsonTree } = await import("@/components/JsonTree")

const payload = {
  user: { name: "Ada", id: 42 },
  cart: { total: 0, items: [] },
}

describe("the object tree's find", () => {
  it("uses the Mac's placeholder, which says keys are searched too", () => {
    // "Find in this object" left you to guess; looking for a field name is the
    // usual reason to open this at all.
    render(<JsonTree value={payload} />)
    expect(screen.getByPlaceholderText("Search keys & values…")).toBeTruthy()
  })

  it("lists matching paths once something is typed", () => {
    render(<JsonTree value={payload} />)
    fireEvent.change(screen.getByPlaceholderText("Search keys & values…"), {
      target: { value: "ada" },
    })
    expect(screen.getByText("user.name")).toBeTruthy()
  })

  it("matches a key as well as a value", () => {
    render(<JsonTree value={payload} />)
    fireEvent.change(screen.getByPlaceholderText("Search keys & values…"), {
      target: { value: "total" },
    })
    expect(screen.getByText("cart.total")).toBeTruthy()
  })

  it("says so rather than showing an empty list", () => {
    render(<JsonTree value={payload} />)
    fireEvent.change(screen.getByPlaceholderText("Search keys & values…"), {
      target: { value: "zzz" },
    })
    expect(screen.getByText("No matches")).toBeTruthy()
  })

  it("tells you a result is clickable, which nothing else does", () => {
    render(<JsonTree value={payload} />)
    fireEvent.change(screen.getByPlaceholderText("Search keys & values…"), {
      target: { value: "ada" },
    })
    expect(screen.getByTitle("Reveal in the tree")).toBeTruthy()
  })

  it("offers a clear only once there is something to clear", () => {
    render(<JsonTree value={payload} />)
    expect(screen.queryByLabelText("Clear the search")).toBeNull()
    fireEvent.change(screen.getByPlaceholderText("Search keys & values…"), {
      target: { value: "ada" },
    })
    fireEvent.click(screen.getByLabelText("Clear the search"))
    expect(screen.queryByText("user.name")).toBeNull()
  })

  it("closes the search on Escape", () => {
    render(<JsonTree value={payload} />)
    const field = screen.getByPlaceholderText("Search keys & values…")
    fireEvent.change(field, { target: { value: "ada" } })
    fireEvent.keyDown(field, { key: "Escape" })
    expect(screen.queryByText("user.name")).toBeNull()
  })
})
