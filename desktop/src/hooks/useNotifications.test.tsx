import { act, renderHook, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const { postNotification, isWindowFocused, onWindowFocusChanged, setFocus } = vi.hoisted(() => {
  let notify: ((focused: boolean) => void) | null = null
  let current = true
  return {
    postNotification: vi.fn(() => Promise.resolve(true)),
    isWindowFocused: vi.fn(() => Promise.resolve(current)),
    onWindowFocusChanged: vi.fn((onChange: (focused: boolean) => void) => {
      notify = onChange
      return Promise.resolve(() => {
        notify = null
      })
    }),
    setFocus: (focused: boolean) => {
      current = focused
      notify?.(focused)
    },
  }
})

vi.mock("@/lib/daemon", () => ({ postNotification }))
vi.mock("@/lib/window-focus", () => ({ isWindowFocused, onWindowFocusChanged }))

const { NotificationsProvider, useNotifications } = await import("@/hooks/useNotifications")

function rendered() {
  return renderHook(() => useNotifications(), { wrapper: NotificationsProvider })
}

const blur = () => {
  act(() => {
    setFocus(false)
  })
}

describe("useNotifications, native side", () => {
  beforeEach(() => {
    postNotification.mockClear()
    setFocus(true)
  })

  it("posts nothing while the window has focus", async () => {
    const hook = rendered()
    act(() => {
      hook.result.current.show({ ok: false, message: "adb refused it" })
    })
    await waitFor(() => expect(hook.result.current.toasts).toHaveLength(1))
    expect(postNotification).not.toHaveBeenCalled()
  })

  it("mirrors an important result once the window is not the one in front", async () => {
    const hook = rendered()
    blur()
    act(() => {
      hook.result.current.show({ ok: false, message: "adb refused it" })
    })
    await waitFor(() => expect(postNotification).toHaveBeenCalledTimes(1))
    expect(postNotification).toHaveBeenCalledWith({
      title: "Task failed",
      body: "adb refused it",
      sound: true,
    })
  })

  it("stays quiet for a routine confirmation even when backgrounded", () => {
    const hook = rendered()
    blur()
    act(() => {
      hook.result.current.show({ ok: true, message: "Copied" })
    })
    expect(postNotification).not.toHaveBeenCalled()
  })

  it("posts a batch summary directly, and only when backgrounded", async () => {
    const hook = rendered()
    act(() => {
      hook.result.current.notifyIfBackgrounded("Install finished", "Installed app.apk")
    })
    expect(postNotification).not.toHaveBeenCalled()

    blur()
    act(() => {
      hook.result.current.notifyIfBackgrounded("Install finished", "Installed app.apk")
    })
    await waitFor(() => expect(postNotification).toHaveBeenCalledTimes(1))
    expect(postNotification).toHaveBeenCalledWith({
      title: "Install finished",
      body: "Installed app.apk",
      sound: false,
    })
    // A summary is not a toast: nothing appears in the window it came from.
    expect(hook.result.current.toasts).toHaveLength(0)
  })

  it("survives a platform that refuses to notify", async () => {
    postNotification.mockRejectedValueOnce(new Error("no notification daemon"))
    const hook = rendered()
    blur()
    act(() => {
      hook.result.current.show({ ok: false, message: "adb refused it" })
    })
    await waitFor(() => expect(hook.result.current.toasts).toHaveLength(1))
    expect(hook.result.current.history).toHaveLength(1)
  })
})
