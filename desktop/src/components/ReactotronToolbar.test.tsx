import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { ReactotronToolbar, ReverseButton } from "@/components/ReactotronToolbar"
import { emptyFilter } from "@/lib/reactotron-filter"

/**
 * The reverse tunnel's button.
 *
 * The device reaches the relay through its own localhost, so without
 * `adb reverse tcp:9090 tcp:9090` nothing connects at all. The Mac keeps the
 * button in the toolbar, always reachable; this app used to offer it only from
 * the status bar, which renders while no client is listed — so a tunnel that
 * dropped with the client still on screen left no way to re-open it.
 */
describe("ReverseButton", () => {
  it("names the command it runs, as the Mac's tooltip does", () => {
    render(<ReverseButton disabled={false} onReverse={vi.fn()} />)
    const button = screen.getByRole("button", { name: /Reverse :9090/u })
    expect(button.title).toBe("Run adb reverse tcp:9090 tcp:9090 on connected devices")
  })

  it("opens the tunnel when pressed", () => {
    const onReverse = vi.fn()
    render(<ReverseButton disabled={false} onReverse={onReverse} />)
    fireEvent.click(screen.getByRole("button", { name: /Reverse :9090/u }))
    expect(onReverse).toHaveBeenCalledOnce()
  })

  it("is disabled with no device, because there is nothing to reverse onto", () => {
    const onReverse = vi.fn()
    render(<ReverseButton disabled onReverse={onReverse} />)
    fireEvent.click(screen.getByRole("button", { name: /Reverse :9090/u }))
    expect(onReverse) .not.toHaveBeenCalled()
  })

  it("rides the toolbar, so a connected client does not hide it", () => {
    // The regression this guards: the button lived in the status bar, which
    // only renders while `clients.length === 0`. Put it in `trailing` and it
    // is on screen whatever the relay is doing.
    render(
      <ReactotronToolbar
        filter={emptyFilter()}
        onFilter={vi.fn()}
        visible={3}
        total={3}
        newestFirst
        onNewestFirst={vi.fn()}
        onOpenFilters={vi.fn()}
        onClear={vi.fn()}
        onExport={vi.fn()}
        onCopyAll={vi.fn()}
      onSplit={vi.fn()}
        trailing={<ReverseButton disabled={false} onReverse={vi.fn()} />}
      />,
    )
    expect(screen.getByRole("button", { name: /Reverse :9090/u })).toBeDefined()
  })
})
