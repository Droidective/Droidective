import { describe, expect, it } from "vitest"
import {
  readCommandEvent,
  runCustomCommand,
  withCommand,
  withoutCommand,
  type CustomCommand,
} from "@/lib/reactotron-commands"

describe("custom commands", () => {
  const ping: CustomCommand = {
    id: 1,
    command: "ping",
    title: "Ping",
    description: null,
    args: ["host", "count"],
  }

  it("reads a registration, taking only the argument names", () => {
    expect(readCommandEvent("customCommand.register", {
      id: 1,
      command: "ping",
      title: "Ping",
      args: [{ name: "host", type: "string" }, { name: "count", type: "string" }],
    })).toEqual({ kind: "register", command: ping })
  })

  it("ignores a registration with no command to run", () => {
    expect(readCommandEvent("customCommand.register", { id: 1, args: [] })).toBeNull()
    expect(readCommandEvent("customCommand.register", { id: 1, command: "" })).toBeNull()
  })

  it("reads an unregister", () => {
    expect(readCommandEvent("customCommand.unregister", { id: 1 }))
      .toEqual({ kind: "unregister", id: 1 })
  })

  it("sends every declared argument, blank ones included", () => {
    // The client indexes by name; an omitted key arrives as undefined where the
    // app expected an empty string.
    expect(runCustomCommand(ping, { host: "example.com" })).toEqual({
      kind: "custom",
      payload: { command: "ping", args: { host: "example.com", count: "" } },
    })
  })

  it("replaces a re-registered command rather than showing it twice", () => {
    // A Fast Refresh re-registers everything the app has.
    const renamed = { ...ping, title: "Ping (v2)" }
    expect(withCommand([ping], renamed)).toEqual([renamed])
    expect(withCommand([ping], { ...ping, id: 2, command: "pong" })).toHaveLength(2)
  })

  it("removes one by id", () => {
    expect(withoutCommand([ping], 1)).toEqual([])
    expect(withoutCommand([ping], 99)).toEqual([ping])
  })
})
