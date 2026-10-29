import { describe, expect, it, vi } from "vitest"

import { listenForStudioApk, openInStudio, pendingStudioApk } from "@/lib/apk-studio"

describe("handing an APK to the studio", () => {
  it("leaves it for a studio that mounts later, and that studio clears it", () => {
    openInStudio("/in/a.apk")
    expect(pendingStudioApk()).toBe("/in/a.apk")
    // Reading twice gives the same answer: a render can run twice.
    expect(pendingStudioApk()).toBe("/in/a.apk")
    const stop = listenForStudioApk(() => {})
    expect(pendingStudioApk()).toBeNull()
    stop()
  })

  it("delivers straight to a studio that is already mounted", () => {
    const heard = vi.fn()
    const stop = listenForStudioApk(heard)
    openInStudio("/in/b.apk")
    expect(heard).toHaveBeenCalledWith("/in/b.apk")
    expect(pendingStudioApk()).toBeNull()
    stop()
    // Once it unmounts, the next one waits for a studio again.
    openInStudio("/in/c.apk")
    expect(heard).toHaveBeenCalledTimes(1)
    expect(pendingStudioApk()).toBe("/in/c.apk")
    listenForStudioApk(() => {})()
  })
})
