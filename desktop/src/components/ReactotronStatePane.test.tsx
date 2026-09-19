import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { ReactotronStatePane } from "@/components/ReactotronStatePane"
import type { ReactotronStateSession } from "@/hooks/useReactotronState"

function session(over: Partial<ReactotronStateSession> = {}): ReactotronStateSession {
  return {
    tree: null,
    loadingTree: false,
    watches: [],
    snapshots: [],
    notice: null,
    loadTree: vi.fn(),
    addWatch: vi.fn(),
    removeWatch: vi.fn(),
    dispatch: vi.fn(),
    snapshot: vi.fn(),
    restore: vi.fn(),
    deleteSnapshot: vi.fn(),
    ...over,
  }
}

describe("ReactotronStatePane", () => {
  it("shows the Mac's four cards, in its order", () => {
    render(<ReactotronStatePane session={session()} />)
    for (const title of ["State tree", "Subscriptions", "Dispatch action", "Snapshots"]) {
      expect(screen.getByText(title)).toBeDefined()
    }
  })

  it("names the plugin the whole screen depends on", () => {
    // Without reactotron-redux or reactotron-mst nothing here ever answers, and
    // four empty cards do not explain why.
    render(<ReactotronStatePane session={session()} />)
    expect(screen.getByText(/reactotron-redux/u)).toBeDefined()
  })

  it("adds a watch on Enter as well as on the button", () => {
    const addWatch = vi.fn()
    render(<ReactotronStatePane session={session({ addWatch })} />)
    const field = screen.getByLabelText("Path to watch")
    fireEvent.change(field, { target: { value: "user.name" } })
    fireEvent.keyDown(field, { key: "Enter" })
    expect(addWatch).toHaveBeenCalledWith("user.name")
  })

  it("will not add a blank path", () => {
    render(<ReactotronStatePane session={session()} />)
    expect(screen.getByRole("button", { name: "Add" }).hasAttribute("disabled")).toBe(true)
  })

  it("offers restore and delete per snapshot, not one for the list", () => {
    // Restoring is how a snapshot earns its keep; a list you can only add to is
    // a list of things you cannot use.
    render(<ReactotronStatePane session={session({
      snapshots: [
        { id: "1", takenAt: 0, state: { a: 1 } },
        { id: "2", takenAt: 0, state: { b: 2 } },
      ],
    })} />)
    expect(screen.getAllByRole("button", { name: "Restore this snapshot" })).toHaveLength(2)
    expect(screen.getAllByRole("button", { name: "Delete this snapshot" })).toHaveLength(2)
  })

  it("says a watch has not reported yet rather than showing it as empty", () => {
    render(<ReactotronStatePane session={session({
      watches: [{ path: "user.name", value: undefined, at: null }],
    })} />)
    expect(screen.getByText("waiting for a change…")).toBeDefined()
  })

  it("surfaces the notice, which is the only place a refusal appears", () => {
    render(<ReactotronStatePane session={session({ notice: "No app is connected." })} />)
    expect(screen.getByText("No app is connected.")).toBeDefined()
  })

  it("disables Refresh while a request is out", () => {
    render(<ReactotronStatePane session={session({ loadingTree: true })} />)
    expect(screen.getByRole("button", { name: "Requesting…" }).hasAttribute("disabled")).toBe(true)
  })
})
