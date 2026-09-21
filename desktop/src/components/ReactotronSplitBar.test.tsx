import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { ReactotronSplitBar } from "@/components/ReactotronSplitBar"

function bar(events: number) {
  const onToggleSplit = vi.fn()
  const onClearAll = vi.fn()
  render(
    <ReactotronSplitBar
      events={events}
      onToggleSplit={onToggleSplit}
      onClearAll={onClearAll}
      trailing={null}
    />,
  )
  return { onToggleSplit, onClearAll }
}

describe("the split timeline's shared strip", () => {
  it("counts the whole buffer, not one pane's view of it", () => {
    // It sits above both panes; a per-pane count there would contradict
    // whichever pane you were not looking at.
    bar(1234)
    expect(screen.getByText("1,234 events")).toBeTruthy()
  })

  it("offers the way back to one pane", () => {
    const { onToggleSplit } = bar(3)
    fireEvent.click(screen.getByLabelText("Back to a single pane"))
    expect(onToggleSplit).toHaveBeenCalledOnce()
  })

  it("says its trash empties both panes, which is the Mac's wording", () => {
    // Each pane's own trash clears only itself; this one frees the shared
    // buffer, and the difference is the whole reason the label is that long.
    const { onClearAll } = bar(3)
    const trash = screen.getByLabelText("Clear the whole timeline — both panes")
    expect(trash.getAttribute("title")).toBe("Clear the whole timeline — both panes")
    fireEvent.click(trash)
    expect(onClearAll).toHaveBeenCalledOnce()
  })

  it("disables the clear with nothing buffered", () => {
    bar(0)
    expect(
      screen.getByLabelText("Clear the whole timeline — both panes").hasAttribute("disabled"),
    ).toBe(true)
  })
})
