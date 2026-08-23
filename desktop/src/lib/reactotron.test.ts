import { describe, expect, it } from "vitest"
import { parseEvent, typedCommandTypes } from "@/lib/reactotron"
import type { JsonValue } from "@/lib/json"
import type { ReactotronCommand } from "@/lib/wire"

/**
 * Decoding Reactotron frames. The cases follow ADBKit's
 * `ReactotronProtocolTests`, because both apps decode the same wire and a row
 * that reads differently on one of them is the bug.
 */

function frame(type: string, payload?: JsonValue): ReactotronCommand {
  return payload === undefined ? { type } : { type, payload }
}

describe("parseEvent", () => {
  it("decodes a client intro", () => {
    const event = parseEvent(
      frame("client.intro", {
        name: "MyApp",
        environment: "development",
        platform: "android",
        reactotronCoreClientVersion: "3.0.0",
      }),
    )
    expect(event).toEqual({
      kind: "clientIntro",
      name: "MyApp",
      environment: "development",
      platform: "android",
      clientVersion: "3.0.0",
    })
  })

  it("falls back to the older version key an intro may use", () => {
    const event = parseEvent(frame("client.intro", { name: "A", reactotronVersion: "2.9" }))
    expect(event.kind === "clientIntro" && event.clientVersion).toBe("2.9")
  })

  it("names an intro that gave no name", () => {
    // A client only sends one once it has been given a name, so a first run has
    // none — and an unnamed row would just read as empty.
    expect(parseEvent(frame("client.intro", {}))).toMatchObject({ kind: "clientIntro", name: "App" })
  })
})

describe("parseEvent, for logs", () => {
  it("decodes a log with its level and stack", () => {
    const event = parseEvent(
      frame("log", {
        level: "warn",
        message: "slow render",
        stack: [{ fileName: "App.tsx", functionName: "render", lineNumber: 12, columnNumber: 4 }],
      }),
    )
    expect(event).toEqual({
      kind: "log",
      level: "warn",
      message: "slow render",
      stack: [{ fileName: "App.tsx", functionName: "render", lineNumber: 12, columnNumber: 4 }],
    })
  })

  it("treats an unknown level as debug", () => {
    expect(parseEvent(frame("log", { level: "trace" }))).toMatchObject({ level: "debug" })
    expect(parseEvent(frame("log", {}))).toMatchObject({ level: "debug" })
  })

  it("previews a logged object rather than showing its shape", () => {
    // `console.log(object)` is common, and a row reading "[object]" tells the
    // reader nothing they could not have guessed.
    const event = parseEvent(frame("log", { message: { userId: 7, name: "ada" } }))
    expect(event).toMatchObject({ message: '{"name":"ada","userId":7}' })
  })

  it("bounds a huge log message", () => {
    const event = parseEvent(frame("log", { message: "x".repeat(10_000) }))
    expect(event.kind === "log" && event.message).toHaveLength(500)
  })

  it("renders a logged scalar as itself", () => {
    expect(parseEvent(frame("log", { message: 42 }))).toMatchObject({ message: "42" })
    expect(parseEvent(frame("log", { message: true }))).toMatchObject({ message: "true" })
    expect(parseEvent(frame("log", { message: null }))).toMatchObject({ message: "null" })
  })

  it("accepts a stack of bare strings as well as of frames", () => {
    const event = parseEvent(frame("log", { stack: ["App.tsx:12", { fileName: "b.ts" }, 7] }))
    expect(event.kind === "log" && event.stack).toEqual([
      { fileName: "App.tsx:12", functionName: "", lineNumber: null, columnNumber: null },
      { fileName: "b.ts", functionName: "", lineNumber: null, columnNumber: null },
    ])
  })
})

describe("parseEvent, for api responses", () => {
  it("decodes an api response from its nested request and response", () => {
    const event = parseEvent(
      frame("api.response", {
        request: { method: "post", url: "https://example.test/v1/users" },
        response: { status: 201 },
        duration: 128.5,
      }),
    )
    expect(event).toMatchObject({
      kind: "apiResponse",
      method: "POST",
      url: "https://example.test/v1/users",
      status: 201,
      duration: 128.5,
    })
  })

  it("reports a request that never got a response as status 0", () => {
    // How a network error arrives from the client. It is not a missing field to
    // paper over — it is the outcome, and the filter has a bucket for it.
    expect(parseEvent(frame("api.response", { request: { url: "u" } }))).toMatchObject({
      status: 0,
      method: "GET",
    })
  })
})

describe("parseEvent, for state, benchmarks and commands", () => {
  it("decodes a benchmark's steps", () => {
    const event = parseEvent(
      frame("benchmark.report", {
        title: "startup",
        steps: [{ title: "mount", time: 10, delta: 4 }, { title: "paint" }],
      }),
    )
    expect(event).toEqual({
      kind: "benchmark",
      title: "startup",
      steps: [
        { title: "mount", time: 10, delta: 4 },
        { title: "paint", time: 0, delta: 0 },
      ],
    })
  })

  it("decodes a state change list", () => {
    const event = parseEvent(
      frame("state.values.change", { changes: [{ path: "user.name", value: "ada" }, {}] }),
    )
    expect(event).toEqual({
      kind: "stateValuesChange",
      changes: [
        { path: "user.name", value: "ada" },
        { path: "", value: null },
      ],
    })
  })

  it("decodes a custom command's registration and its removal", () => {
    const registered = parseEvent(
      frame("customCommand.register", {
        id: 3,
        command: "reset",
        title: "Reset",
        args: [{ name: "scope" }],
      }),
    )
    expect(registered).toEqual({
      kind: "customCommandRegister",
      id: 3,
      command: "reset",
      title: "Reset",
      description: undefined,
      args: [{ name: "scope", type: "string" }],
    })
    expect(parseEvent(frame("customCommand.unregister", { id: 3, command: "reset" }))).toEqual({
      kind: "customCommandUnregister",
      id: 3,
      command: "reset",
    })
  })

  it("decodes an image from either a bare uri or an object", () => {
    expect(parseEvent(frame("display", { image: "data:image/png;base64,AA" }))).toMatchObject({
      image: "data:image/png;base64,AA",
    })
    expect(parseEvent(frame("display", { image: { uri: "https://x.test/a.png" } }))).toMatchObject({
      image: "https://x.test/a.png",
    })
  })

  it("decodes the repl responses", () => {
    expect(parseEvent(frame("repl.ls.response", ["a", 1, "b"]))).toEqual({
      kind: "replKeys",
      names: ["a", "b"],
    })
    expect(parseEvent(frame("repl.execute.response", { ok: true }))).toEqual({
      kind: "replResult",
      value: { ok: true },
    })
  })
})

describe("parseEvent, for what it does not recognise", () => {
  it("shows a frame it has no case for rather than dropping it", () => {
    // Sagas and the devtools pokes land here, and so does anything upstream
    // adds next. A timeline that omitted them would read as the app gone quiet.
    expect(parseEvent(frame("saga.task.complete", { name: "fetchUser" }))).toEqual({
      kind: "unknown",
      type: "saga.task.complete",
      payload: { name: "fetchUser" },
    })
    expect(parseEvent(frame("something.new"))).toEqual({
      kind: "unknown",
      type: "something.new",
      payload: undefined,
    })
  })

  it("decodes every frame with no payload at all", () => {
    // A client may omit it entirely — `clear` always does. Every parser has to
    // survive that, so this walks the whole table rather than trusting review.
    for (const type of typedCommandTypes) {
      expect(() => parseEvent({ type })).not.toThrow()
    }
  })

  it("covers exactly upstream's typed command list", () => {
    // The set is the contract with `reactotron-core-contract`. A type dropped
    // here silently demotes its rows to "unknown", which looks like a styling
    // regression rather than a missing decoder.
    expect(typedCommandTypes.toSorted()).toEqual(
      [
        "api.response",
        "asyncStorage.mutation",
        "benchmark.report",
        "clear",
        "client.intro",
        "customCommand.register",
        "customCommand.unregister",
        "display",
        "image",
        "log",
        "repl.execute.response",
        "repl.ls.response",
        "state.action.complete",
        "state.backup.response",
        "state.keys.response",
        "state.values.change",
        "state.values.response",
      ].toSorted(),
    )
  })
})
