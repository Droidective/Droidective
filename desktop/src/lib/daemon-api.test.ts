import { describe, expect, it } from "vitest"

import { normaliseSendResponse } from "@/lib/daemon-api"

/**
 * Swift's `JSONEncoder` omits a nil optional rather than writing `null`, so
 * every field the daemon left empty reaches this side as `undefined`.
 *
 * That is not a cosmetic difference. A `!== null` test passes for `undefined`,
 * which is exactly how a response with no body became
 * `data:image/png;base64,undefined` in the pane — found by sending a real
 * request through a running daemon, not by reading the types.
 */
describe("normaliseSendResponse", () => {
  it("turns every omitted field into the null or empty value the pane reads", () => {
    const answer = normaliseSendResponse({
      statusCode: 200,
      statusText: "OK",
      headers: [{ key: "Content-Type", value: "application/json" }],
      cookies: [],
      bodyText: '{"a":1}',
      bodyOmitted: false,
      format: "json",
      mediaType: "application/json",
      elapsedMs: 12,
      size: 7,
      sizeText: "7 B",
      truncated: false,
      redirects: [],
      finalURL: "https://example.test",
      sentBytes: 0,
      preparedURL: "https://example.test",
      assertions: [],
      warnings: [],
      // The three the daemon leaves out for a plain JSON answer.
      prettyBody: undefined,
      bodyBase64: undefined,
      timing: undefined,
    })

    expect(answer.bodyBase64).toBeNull()
    expect(answer.prettyBody).toBeNull()
    expect(answer.timing).toBeNull()
    // And nothing that was present is disturbed.
    expect(answer.bodyText).toBe('{"a":1}')
    expect(answer.statusCode).toBe(200)
  })

  /**
   * A reply this build cannot read should still draw an empty pane rather than
   * throwing on the first field the response pane touches.
   */
  it("survives a reply with nothing in it at all", () => {
    const answer = normaliseSendResponse({} as never)
    expect(answer.statusCode).toBe(0)
    expect(answer.headers).toEqual([])
    expect(answer.assertions).toEqual([])
    expect(answer.sizeText).toBe("0 B")
    expect(answer.format).toBe("text")
  })
})
