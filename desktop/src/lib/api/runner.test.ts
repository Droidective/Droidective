import { describe, expect, it } from "vitest"

import { newFolder, newRequest } from "@/lib/api/defaults"
import type { ApiItem } from "@/lib/api/model"
import {
  DEFAULT_RUN_OPTIONS,
  effectiveIterations,
  flatten,
  headline,
  plannedCount,
  rowPassed,
  shouldStop,
  summarise,
  type RunRow,
} from "@/lib/api/runner"

function requestItem(name: string): ApiItem {
  return { kind: "request", request: { ...newRequest(), name } }
}

function folderItem(name: string, items: ApiItem[]): ApiItem {
  return { kind: "folder", folder: { ...newFolder(name), items } }
}

function row(over: Partial<RunRow> = {}): RunRow {
  return {
    id: "r",
    iteration: 1,
    name: "One",
    path: [],
    method: "GET",
    url: "https://example.test",
    statusCode: 200,
    elapsedMs: 10,
    errorText: null,
    assertions: [],
    ...over,
  }
}

describe("flatten", () => {
  it("walks depth-first and carries the folders that lead to each request", () => {
    const plan = flatten([
      requestItem("Health"),
      folderItem("Orders", [requestItem("List"), folderItem("Writes", [requestItem("Create")])]),
    ])
    expect(plan.map((step) => [step.request.name, step.path])).toEqual([
      ["Health", []],
      ["List", ["Orders"]],
      ["Create", ["Orders", "Writes"]],
    ])
  })

  it("has nothing to do with an empty collection", () => {
    expect(flatten([])).toEqual([])
  })
})

describe("effectiveIterations", () => {
  it("is at least one and at most a hundred", () => {
    expect(effectiveIterations({ ...DEFAULT_RUN_OPTIONS, iterations: 1 })).toBe(1)
    expect(effectiveIterations({ ...DEFAULT_RUN_OPTIONS, iterations: 0 })).toBe(1)
    expect(effectiveIterations({ ...DEFAULT_RUN_OPTIONS, iterations: -5 })).toBe(1)
    expect(effectiveIterations({ ...DEFAULT_RUN_OPTIONS, iterations: 5000 })).toBe(100)
  })

  /**
   * The field is a text box, so an empty one arrives as `NaN`. Without this it
   * would take the `Math.max` branch and run zero times, which reads as a Run
   * button that does nothing.
   */
  it("treats a field that is not a number as one iteration", () => {
    expect(effectiveIterations({ ...DEFAULT_RUN_OPTIONS, iterations: Number.NaN })).toBe(1)
  })
})

describe("rowPassed", () => {
  it("needs a 2xx", () => {
    expect(rowPassed(row())).toBe(true)
    expect(rowPassed(row({ statusCode: 404 }))).toBe(false)
    expect(rowPassed(row({ statusCode: 302 }))).toBe(false)
    expect(rowPassed(row({ statusCode: null }))).toBe(false)
  })

  it("fails on a request that never got an answer", () => {
    expect(rowPassed(row({ errorText: "No response within 60s" }))).toBe(false)
  })

  /** A 2xx with a failed assertion is a failure — that is what tests are for. */
  it("needs every assertion to hold as well", () => {
    const failing = [{ id: "a", label: "Status code equals 201", passed: false, detail: "200" }]
    expect(rowPassed(row({ assertions: failing }))).toBe(false)
    expect(rowPassed(row({ assertions: [{ ...failing[0], passed: true } as never] }))).toBe(true)
  })
})

describe("summarise and headline", () => {
  it("counts passes, failures and assertions", () => {
    const summary = summarise(
      [
        row(),
        row({ statusCode: 500 }),
        row({ assertions: [{ id: "a", label: "l", passed: true, detail: "" }] }),
      ],
      2500,
      false,
    )
    expect(summary).toEqual({
      passed: 2,
      failed: 1,
      assertions: 1,
      totalMs: 2500,
      cancelled: false,
    })
  })

  /** The Mac's own sentence, down to the singular assertion. */
  it("reads the way the Mac's headline reads", () => {
    expect(headline(summarise([row()], 2500, false), 1)).toBe("1/1 passed · 0 assertions · 2.5s")
    expect(
      headline(
        summarise([row({ assertions: [{ id: "a", label: "l", passed: true, detail: "" }] })], 1000, false),
        1,
      ),
    ).toBe("1/1 passed · 1 assertion · 1.0s")
  })
})

describe("shouldStop", () => {
  it("stops on a row that did not pass, only when asked to", () => {
    const failed = row({ statusCode: 500 })
    expect(shouldStop({ ...DEFAULT_RUN_OPTIONS, stopOnFailure: true }, failed)).toBe(true)
    expect(shouldStop(DEFAULT_RUN_OPTIONS, failed)).toBe(false)
    expect(shouldStop({ ...DEFAULT_RUN_OPTIONS, stopOnFailure: true }, row())).toBe(false)
  })
})

describe("plannedCount", () => {
  it("multiplies the requests by the iterations the run will actually do", () => {
    const items = [requestItem("One"), folderItem("F", [requestItem("Two")])]
    expect(plannedCount(items, DEFAULT_RUN_OPTIONS)).toBe(2)
    expect(plannedCount(items, { ...DEFAULT_RUN_OPTIONS, iterations: 3 })).toBe(6)
    expect(plannedCount(items, { ...DEFAULT_RUN_OPTIONS, iterations: 1000 })).toBe(200)
  })
})
