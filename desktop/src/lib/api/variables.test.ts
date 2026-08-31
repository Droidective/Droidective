import { describe, expect, it } from "vitest"

import { newRequest } from "@/lib/api/defaults"
import type { ApiClientData } from "@/lib/api/model"
import {
  EMPTY_SCOPE,
  expandOnce,
  merged,
  origin,
  resolve,
  scopeFor,
  unresolvedInRequest,
  unresolvedNames,
  type VariableScope,
} from "@/lib/api/variables"

function scope(over: Partial<VariableScope> = {}): VariableScope {
  return { ...EMPTY_SCOPE, ...over }
}

describe("expandOnce", () => {
  it("substitutes a name and leaves the rest of the string alone", () => {
    expect(expandOnce("a {{x}} b", (name) => (name === "x" ? "1" : null))).toBe("a 1 b")
  })

  /**
   * The whole point of returning the reference: an unknown variable has to be
   * visible in the URL bar, not silently an empty string in the request.
   */
  it("leaves an unknown reference written as it was", () => {
    expect(expandOnce("{{host}}/orders", () => null)).toBe("{{host}}/orders")
  })

  it("trims whitespace inside the braces but keeps it when unresolved", () => {
    expect(expandOnce("{{ x }}", (name) => (name === "x" ? "1" : null))).toBe("1")
    expect(expandOnce("{{ x }}", () => null)).toBe("{{ x }}")
  })

  it("passes an unclosed opener through", () => {
    expect(expandOnce("{{x", () => "1")).toBe("{{x")
    expect(expandOnce("a {{x", () => "1")).toBe("a {{x")
  })

  it("refuses an empty name and a nested opener", () => {
    expect(expandOnce("{{}}", () => "1")).toBe("{{}}")
    expect(expandOnce("{{a{{b}}}}", () => "1")).toBe("{{a1}}")
  })

  it("substitutes every occurrence, not just the first", () => {
    expect(expandOnce("{{x}}-{{x}}", () => "1")).toBe("1-1")
  })
})

describe("merged and origin", () => {
  it("lets each layer beat the one below it", () => {
    const layers = scope({
      globals: { host: "global", only: "g" },
      environment: { host: "env" },
      collection: { host: "collection" },
      local: { host: "local" },
    })
    expect(merged(layers)["host"]).toBe("local")
    expect(merged(layers)["only"]).toBe("g")
  })

  it("names the layer a value came from", () => {
    const layers = scope({ globals: { a: "1" }, collection: { b: "2" } })
    expect(origin(layers, "b")).toBe("collection")
    expect(origin(layers, "a")).toBe("global")
    expect(origin(layers, "c")).toBeNull()
  })
})

describe("resolve", () => {
  it("expands a value that itself references another variable", () => {
    const layers = scope({ globals: { base: "{{scheme}}://example.test", scheme: "https" } })
    expect(resolve("{{base}}/orders", layers)).toBe("https://example.test/orders")
  })

  /**
   * A cycle terminates by the depth cap rather than by hanging, and what is
   * left is the reference — which is also what tells someone they wrote one.
   */
  it("stops on a reference cycle instead of looping", () => {
    const layers = scope({ globals: { a: "{{b}}", b: "{{a}}" } })
    expect(resolve("{{a}}", layers)).toContain("{{")
  })

  it("returns the template untouched when there is nothing to resolve", () => {
    expect(resolve("https://example.test", scope({ globals: { a: "1" } }))).toBe(
      "https://example.test",
    )
  })
})

describe("unresolvedNames", () => {
  it("lists each missing name once, in the order it appears", () => {
    expect(unresolvedNames("{{host}}/{{path}}/{{host}}", EMPTY_SCOPE)).toEqual(["host", "path"])
  })

  it("says nothing about a name the scope can resolve", () => {
    expect(unresolvedNames("{{host}}", scope({ globals: { host: "x" } }))).toEqual([])
  })

  /**
   * The dynamic names resolve at send time, so warning about them would flag
   * the one kind of variable that always works.
   */
  it("does not warn about the dynamic variables", () => {
    expect(unresolvedNames("{{$guid}}-{{$timestamp}}", EMPTY_SCOPE)).toEqual([])
  })
})

describe("unresolvedInRequest", () => {
  it("scans the URL, the enabled rows, the body and the auth", () => {
    const request = {
      ...newRequest(),
      url: "{{host}}/orders",
      headers: [
        { id: "h1", key: "X-{{tenant}}", value: "1", enabled: true, note: "" },
        { id: "h2", key: "X-{{skipped}}", value: "1", enabled: false, note: "" },
      ],
      body: { ...newRequest().body, type: "json" as const, jsonText: '{"id":"{{orderId}}"}' },
      auth: { ...newRequest().auth, bearerToken: "{{token}}" },
    }

    expect(unresolvedInRequest(request, EMPTY_SCOPE)).toEqual([
      "host",
      "tenant",
      "orderId",
      "token",
    ])
  })

  /**
   * A disabled row is not sent, so warning about it would be warning about
   * something that cannot go wrong.
   */
  it("ignores a disabled row", () => {
    const request = {
      ...newRequest(),
      queryParams: [{ id: "q1", key: "page", value: "{{page}}", enabled: false, note: "" }],
    }
    expect(unresolvedInRequest(request, EMPTY_SCOPE)).toEqual([])
  })

  it("scans only the body kind that is selected", () => {
    const base = newRequest()
    const request = {
      ...base,
      body: {
        ...base.body,
        type: "raw" as const,
        rawText: "{{inRaw}}",
        jsonText: "{{inJson}}",
      },
    }
    expect(unresolvedInRequest(request, EMPTY_SCOPE)).toEqual(["inRaw"])
  })
})

describe("scopeFor", () => {
  const data: ApiClientData = {
    collections: [],
    environments: [
      { id: "e1", name: "Staging", variables: [{ id: "v1", key: "host", value: "stage", enabled: true, note: "" }] },
    ],
    activeEnvironmentId: "e1",
    globals: [{ id: "g1", key: "token", value: "abc", enabled: true, note: "" }],
    history: [],
  }

  it("takes globals, the active environment and the collection", () => {
    const layers = scopeFor(data, {
      id: "c1",
      name: "Orders",
      note: "",
      items: [],
      variables: [{ id: "cv1", key: "host", value: "collection", enabled: true, note: "" }],
      auth: newRequest().auth,
      createdAt: 0,
    })
    expect(layers.globals["token"]).toBe("abc")
    expect(layers.environment["host"]).toBe("stage")
    expect(merged(layers)["host"]).toBe("collection")
  })

  it("leaves the environment empty when none is active", () => {
    const layers = scopeFor({ ...data, activeEnvironmentId: null }, null)
    expect(layers.environment).toEqual({})
    expect(layers.globals["token"]).toBe("abc")
  })

  /** A disabled variable is not a value — `activeMap` skips it. */
  it("skips a disabled variable", () => {
    const layers = scopeFor(
      { ...data, globals: [{ id: "g1", key: "token", value: "abc", enabled: false, note: "" }] },
      null,
    )
    expect(layers.globals).toEqual({})
  })
})
