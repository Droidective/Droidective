import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { ReactotronCommandsPane } from "@/components/ReactotronCommandsPane"
import type { ReactotronCommandsSession } from "@/hooks/useReactotronCommands"
import type { CustomCommand } from "@/lib/reactotron-commands"

const ping: CustomCommand = {
  id: 1,
  command: "ping",
  title: "Ping the server",
  description: "Sends one request.",
  args: ["host", "count"],
}

function session(over: Partial<ReactotronCommandsSession> = {}): ReactotronCommandsSession {
  return { commands: [], notice: null, run: vi.fn(), ...over }
}

describe("ReactotronCommandsPane", () => {
  it("explains how commands get here, because the screen cannot ask for any", () => {
    // The client announces them on connect. An empty list is the ordinary
    // state, not a failure, so it has to say what would fill it.
    render(<ReactotronCommandsPane session={session()} />)
    expect(screen.getByText("No custom commands")).toBeDefined()
    expect(screen.getByText(/Reactotron\.onCustomCommand/u)).toBeDefined()
  })

  it("shows the command's own name even when a title stands in front of it", () => {
    // The title is for reading; the name is what the app calls the handler and
    // what someone greps for.
    render(<ReactotronCommandsPane session={session({ commands: [ping] })} />)
    expect(screen.getByText("Ping the server")).toBeDefined()
    expect(screen.getByText("ping")).toBeDefined()
  })

  it("gives every declared argument a field", () => {
    render(<ReactotronCommandsPane session={session({ commands: [ping] })} />)
    expect(screen.getByLabelText("host")).toBeDefined()
    expect(screen.getByLabelText("count")).toBeDefined()
  })

  it("runs with what was typed", () => {
    const run = vi.fn()
    render(<ReactotronCommandsPane session={session({ commands: [ping], run })} />)
    fireEvent.change(screen.getByLabelText("host"), { target: { value: "example.com" } })
    fireEvent.click(screen.getByRole("button", { name: /Run/u }))
    expect(run).toHaveBeenCalledWith(ping, { host: "example.com" })
  })

  it("runs a command that takes no arguments at all", () => {
    const run = vi.fn()
    const bare: CustomCommand = { id: 2, command: "reset", title: null, description: null, args: [] }
    render(<ReactotronCommandsPane session={session({ commands: [bare], run })} />)
    fireEvent.click(screen.getByRole("button", { name: /Run/u }))
    expect(run).toHaveBeenCalledWith(bare, {})
  })

  it("keeps each card's fields to itself", () => {
    // Two commands can declare the same argument name; typing into one must
    // not fill the other.
    const other: CustomCommand = {
      id: 2, command: "trace", title: null, description: null, args: ["host"],
    }
    const run = vi.fn()
    render(<ReactotronCommandsPane session={session({ commands: [ping, other], run })} />)
    const [first, second] = screen.getAllByLabelText("host")
    fireEvent.change(first as HTMLElement, { target: { value: "a.example" } })
    expect((second as HTMLInputElement).value).toBe("")
  })

  it("reports what happened after a run", () => {
    render(<ReactotronCommandsPane session={session({ commands: [ping], notice: "Sent “ping”" })} />)
    expect(screen.getByText("Sent “ping”")).toBeDefined()
  })
})
