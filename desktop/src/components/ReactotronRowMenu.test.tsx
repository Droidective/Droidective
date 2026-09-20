import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { ReactotronRowMenu } from "@/components/ReactotronRowMenu"
import type { TimelineRow } from "@/lib/reactotron-rows"

function row(): TimelineRow {
  return {
    id: 1,
    event: { kind: "log", level: "debug", message: "hello" } as unknown as TimelineRow["event"],
    command: { type: "log", payload: { message: "hello" } } as unknown as TimelineRow["command"],
    connection: 1,
    important: false,
    bytes: 32,
    receivedAt: Date.UTC(2026, 8, 20, 12, 0, 0, 0),
  } as unknown as TimelineRow
}

function menu(selectionCount: number) {
  const onCopySelection = vi.fn()
  const onCopy = vi.fn()
  render(
    <ReactotronRowMenu
      at={{ x: 10, y: 10 }}
      row={row()}
      onDismiss={vi.fn()}
      onCopy={onCopy}
      selectionCount={selectionCount}
      onCopySelection={onCopySelection}
    />,
  )
  return { onCopySelection, onCopy }
}

describe("the row's right-click menu", () => {
  it("always offers the row's own verbs", () => {
    menu(0)
    expect(screen.getByRole("menuitem", { name: "Copy line" })).toBeTruthy()
    expect(screen.getByRole("menuitem", { name: "Copy object" })).toBeTruthy()
  })

  it("keeps the bulk verbs out until more than one row is picked", () => {
    // With a single row picked they would say the same thing as Copy line,
    // twice — which is why the Mac gates them past one.
    menu(1)
    expect(screen.queryByRole("menuitem", { name: /Selected/u })).toBeNull()
  })

  it("names the count in both bulk verbs", () => {
    menu(4)
    expect(screen.getByRole("menuitem", { name: "Copy 4 Selected Events" })).toBeTruthy()
    expect(screen.getByRole("menuitem", { name: "Copy 4 Selected as JSON" })).toBeTruthy()
  })

  it("asks for the plain copy or the JSON one", () => {
    const { onCopySelection } = menu(2)
    fireEvent.click(screen.getByRole("menuitem", { name: "Copy 2 Selected Events" }))
    expect(onCopySelection).toHaveBeenCalledWith(false)
  })

  it("asks for JSON from the JSON item", () => {
    const { onCopySelection } = menu(2)
    fireEvent.click(screen.getByRole("menuitem", { name: "Copy 2 Selected as JSON" }))
    expect(onCopySelection).toHaveBeenCalledWith(true)
  })
})
