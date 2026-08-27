/**
 * Metro's target list, against the shapes it really serves.
 *
 * The rules are ADBKit's `MetroInspector`: the two apps must pick the same
 * target out of the same list. Connecting to Metro's own placeholder entry
 * succeeds and then delivers nothing, which is the worst kind of wrong.
 */

import { describe, expect, it } from "vitest"

import { isHermes, isLocalDebuggerUrl, parseTargets, targetLabel } from "@/lib/metro"

const HERMES = {
  id: "1",
  title: "Hermes React Native",
  appId: "com.streamlab",
  description: "StreamLab",
  deviceName: "Pixel 7",
  vm: "Hermes",
  webSocketDebuggerUrl: "ws://localhost:8081/inspector/debug?device=1&page=1",
  reactNative: { logicalDeviceId: "abc-123" },
}

describe("parseTargets", () => {
  it("reads a Hermes target whole", () => {
    const [target] = parseTargets([HERMES])
    expect(target).toMatchObject({
      id: "1",
      title: "Hermes React Native",
      appId: "com.streamlab",
      detail: "StreamLab",
      deviceName: "Pixel 7",
      vm: "Hermes",
      logicalDeviceId: "abc-123",
    })
  })

  it("drops Metro's own placeholder entry", () => {
    // Metro lists this on purpose; connecting to it delivers nothing.
    const placeholder = { ...HERMES, id: "2", vm: "don't use" }
    expect(parseTargets([HERMES, placeholder]).map((one) => one.id)).toEqual(["1"])
  })

  it("drops an entry with no socket to connect to", () => {
    expect(parseTargets([{ id: "3", title: "x" }])).toEqual([])
    expect(parseTargets([{ ...HERMES, webSocketDebuggerUrl: "" }])).toEqual([])
  })

  it("puts Hermes first, keeping Metro's order within each group", () => {
    const other = { ...HERMES, id: "9", vm: "JSC" }
    const another = { ...HERMES, id: "8", vm: "JSC" }
    const second = { ...HERMES, id: "2" }
    const ids = parseTargets([other, HERMES, another, second]).map((one) => one.id)
    expect(ids).toEqual(["1", "2", "9", "8"])
  })

  it("falls back rather than dropping a sparse entry", () => {
    const [target] = parseTargets([{ webSocketDebuggerUrl: "ws://localhost:8081/x" }])
    expect(target?.id).toBe("ws://localhost:8081/x")
    expect(target?.title).toBe("React Native")
    expect(target?.detail).toBe("")
  })

  it("uses appId as the detail when there is no description", () => {
    const [target] = parseTargets([{ ...HERMES, description: undefined }])
    expect(target?.detail).toBe("com.streamlab")
  })

  it("answers nothing for anything that is not a list", () => {
    expect(parseTargets(null)).toEqual([])
    expect(parseTargets({})).toEqual([])
    expect(parseTargets("nope")).toEqual([])
    expect(parseTargets([null, 3, "x"])).toEqual([])
  })
})

describe("isHermes", () => {
  it("is the vm name, exactly", () => {
    expect(isHermes({ ...HERMES, vm: "Hermes" } as never)).toBe(true)
    expect(isHermes({ ...HERMES, vm: "JSC" } as never)).toBe(false)
    expect(isHermes({ ...HERMES, vm: null } as never)).toBe(false)
  })
})

/**
 * The socket lives in the webview here, so this check matters more than it does
 * on the Mac: it is what stops a rogue process on the Metro port from steering
 * the console at an off-host WebSocket.
 */
describe("isLocalDebuggerUrl", () => {
  it("accepts loopback ws and wss", () => {
    expect(isLocalDebuggerUrl("ws://localhost:8081/inspector/debug")).toBe(true)
    expect(isLocalDebuggerUrl("ws://127.0.0.1:8081/x")).toBe(true)
    expect(isLocalDebuggerUrl("wss://localhost:8081/x")).toBe(true)
    expect(isLocalDebuggerUrl("ws://[::1]:8081/x")).toBe(true)
  })

  it("refuses another host", () => {
    expect(isLocalDebuggerUrl("ws://evil.example.com/x")).toBe(false)
    expect(isLocalDebuggerUrl("ws://10.0.0.5:8081/x")).toBe(false)
  })

  it("refuses a scheme that is not a WebSocket", () => {
    expect(isLocalDebuggerUrl("http://localhost:8081/x")).toBe(false)
    expect(isLocalDebuggerUrl("file:///etc/passwd")).toBe(false)
  })

  it("refuses something that is not a URL at all", () => {
    expect(isLocalDebuggerUrl("")).toBe(false)
    expect(isLocalDebuggerUrl("not a url")).toBe(false)
  })

  it("is not fooled by a host that merely contains localhost", () => {
    expect(isLocalDebuggerUrl("ws://localhost.evil.com/x")).toBe(false)
  })
})

describe("targetLabel", () => {
  it("names the device and the target", () => {
    expect(targetLabel(parseTargets([HERMES])[0] as never)).toBe("Pixel 7 · Hermes React Native")
  })

  it("falls back to the id when there is nothing to name", () => {
    const [target] = parseTargets([{ webSocketDebuggerUrl: "ws://localhost:8081/x", title: "" }])
    expect(targetLabel(target as never)).toBe("ws://localhost:8081/x")
  })
})
