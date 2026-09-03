import { describe, expect, it } from "vitest"

import { emptyWorkspace, newCollection, newRequest } from "@/lib/api/defaults"
import type { ApiClientData, SavedRequest } from "@/lib/api/model"
import { addCollection, hasUnsavedChanges, saveRequest } from "@/lib/api/workspace"

/**
 * The dirty-check that drives the New Request confirmation. Split out of
 * `workspace.test.ts` to keep both files inside the 300-line lint cap.
 */
function withCollection(): { data: ApiClientData; id: string } {
  const collection = { ...newCollection("Orders"), id: "c1" }
  return { data: addCollection(emptyWorkspace(), collection), id: "c1" }
}

function request(over: Partial<SavedRequest> = {}): SavedRequest {
  return { ...newRequest(), id: "r1", name: "List", url: "https://example.test", ...over }
}

describe("hasUnsavedChanges", () => {
  it("is false for an empty scratch request and true once a URL is typed", () => {
    expect(hasUnsavedChanges(emptyWorkspace(), { ...newRequest(), url: "" }, null)).toBe(false)
    expect(hasUnsavedChanges(emptyWorkspace(), request(), null)).toBe(true)
  })

  it("is false for a request that matches what is stored", () => {
    const { data, id } = withCollection()
    const saved = saveRequest(data, request(), id, null)
    expect(hasUnsavedChanges(saved, request(), id)).toBe(false)
  })

  /**
   * `modifiedAt` moves on every save, so comparing it would call a request
   * dirty the instant it was saved — which is the confirmation firing on every
   * New Request.
   */
  it("ignores the modified timestamp", () => {
    const { data, id } = withCollection()
    const saved = saveRequest(data, request({ modifiedAt: 1 }), id, null)
    expect(hasUnsavedChanges(saved, request({ modifiedAt: 999 }), id)).toBe(false)
  })

  /**
   * `createdAt` is stable for one request but not across two constructions of
   * the same content — `newRequest()` stamps it from the clock — so a request
   * rebuilt from defaults (an import, a Postman round-trip) reported changes
   * nobody made.
   */
  it("ignores the created timestamp", () => {
    const { data, id } = withCollection()
    const saved = saveRequest(data, request({ createdAt: 1, modifiedAt: 2 }), id, null)
    expect(hasUnsavedChanges(saved, request({ createdAt: 998, modifiedAt: 999 }), id)).toBe(false)
  })

  /**
   * The same rule via the clock, which is how it was found: "matches what is
   * stored" above builds two fixtures back to back and only held while both
   * landed in the same millisecond, so it failed in CI once a run straddled a
   * tick. Waiting for a guaranteed tick fails every time before the fix and
   * passes every time after, rather than once in a while either way.
   */
  it("matches a request built a clock tick later", async () => {
    const { data, id } = withCollection()
    const saved = saveRequest(data, request(), id, null)
    await new Promise<void>((resolve) => {
      setTimeout(resolve, 2)
    })
    expect(hasUnsavedChanges(saved, request(), id)).toBe(false)
  })

  it("is true once a field actually changes", () => {
    const { data, id } = withCollection()
    const saved = saveRequest(data, request(), id, null)
    expect(hasUnsavedChanges(saved, request({ method: "POST" }), id)).toBe(true)
  })
})

