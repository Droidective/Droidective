import { describe, expect, it } from "vitest"
import { curlCommand, formParts, shellQuote, urlMergingParams } from "@/lib/reactotron-curl"

/**
 * The cURL builder, following ADBKit's `ReactotronCurlTests`.
 *
 * This is the one thing in the timeline someone takes *out* of the app and
 * runs, so every case here is a way the naive command would reproduce something
 * other than what the app sent.
 */
describe("shellQuote", () => {
  it("wraps a value and closes any quote inside it", () => {
    expect(shellQuote("plain")).toBe("'plain'")
    expect(shellQuote("it's")).toBe(String.raw`'it'\''s'`)
  })

  it("leaves the metacharacters a shell would otherwise read", () => {
    // Inside single quotes these are literal, which is the whole point.
    expect(shellQuote("a&b;c|d $HOME `x`")).toBe("'a&b;c|d $HOME `x`'")
  })
})

describe("curlCommand", () => {
  it("builds a body-less GET without stating the verb", () => {
    const command = curlCommand({ method: "get", url: "https://x.test/a" })
    expect(command).toBe("curl \\\n  'https://x.test/a'")
  })

  it("states the verb whenever a body rides along", () => {
    // curl switches to POST the moment there is a body, so a GET carrying one
    // would silently become a POST.
    const command = curlCommand({
      method: "GET",
      url: "https://x.test/a",
      request: { data: '{"q":1}' },
    })
    expect(command).toContain("-X GET")
    expect(command).toContain(`--data '{"q":1}'`)
  })

  it("sorts headers and renders a non-string one as JSON", () => {
    const command = curlCommand({
      method: "POST",
      url: "https://x.test/a",
      request: { headers: { "X-B": "two", "X-A": "one", "X-N": 7 } },
    })
    expect(command.indexOf("X-A")).toBeLessThan(command.indexOf("X-B"))
    expect(command).toContain("-H 'X-N: 7'")
  })

  it("sends no body for a payload that means nothing", () => {
    // Keeping a body-less GET body-less is what keeps it a GET.
    for (const data of ["", "{}", "[]", "null", null]) {
      const command = curlCommand({ method: "GET", url: "https://x.test/a", request: { data } })
      expect(command, JSON.stringify(data)).not.toContain("--data")
      expect(command).not.toContain("-X")
    }
  })

  it("rebuilds a React Native FormData body as form fields", () => {
    // `{"_parts": [[name, value]]}` attached as --data reproduces nothing.
    const command = curlCommand({
      method: "POST",
      url: "https://x.test/upload",
      request: {
        headers: { "Content-Type": "multipart/form-data; boundary=--stale" },
        data: { _parts: [["caption", "hello"], ["file", { uri: "file:///a.jpg", name: "a.jpg" }]] },
      },
    })
    expect(command).toContain("--form-string 'caption=hello'")
    // A file lives on the device and cannot ride a copied command, so the part
    // travels as its JSON rather than pretending to be a local path.
    expect(command).toContain(`--form-string 'file={"name":"a.jpg","uri":"file:///a.jpg"}'`)
    // The captured boundary is stale — curl has to mint its own.
    expect(command).not.toContain("Content-Type")
    expect(command).not.toContain("--data")
  })

  it("uses --form-string so a value starting with @ is not read as a file", () => {
    const command = curlCommand({
      method: "POST",
      url: "https://x.test/u",
      request: { data: { _parts: [["handle", "@someone"]] } },
    })
    expect(command).toContain("--form-string 'handle=@someone'")
    expect(command).not.toMatch(/ -F /u)
  })

  it("ignores a _parts shape that is not one", () => {
    // A FormData body is `_parts` and nothing else. Anything with a second key
    // is an ordinary object that happens to contain one, so it travels as a
    // body rather than being half-rebuilt as a form.
    const command = curlCommand({
      method: "POST",
      url: "u",
      request: { data: { _parts: [["a", "b"]], other: 1 } },
    })
    expect(command).toContain("--data")
    expect(command).not.toContain("--form-string")
    expect(formParts({ _parts: [["a", "b"]], other: 1 })).toBeNull()
    expect(formParts({ _parts: ["not-a-pair"] })).toBeNull()
    expect(formParts({ _parts: [] })).toBeNull()
    expect(formParts("not an object")).toBeNull()
  })
})

describe("urlMergingParams", () => {
  it("appends the params a rewritten url lost", () => {
    // The plugin reports `xhr.responseURL` — the URL after a redirect, which can
    // arrive without the query the app actually sent.
    expect(urlMergingParams("https://x.test/a", { page: 2, sort: "name" })).toBe(
      "https://x.test/a?page=2&sort=name",
    )
  })

  it("does nothing when the url kept its query", () => {
    expect(urlMergingParams("https://x.test/a?page=2", { page: 2 })).toBe("https://x.test/a?page=2")
  })

  it("matches a key the client percent-encoded", () => {
    // Some client versions decode param keys and some do not, so either
    // spelling counts as already present.
    expect(urlMergingParams("https://x.test/a?my%20key=1", { "my key": 1 })).toBe(
      "https://x.test/a?my%20key=1",
    )
  })

  it("repeats a key for an array value", () => {
    expect(urlMergingParams("https://x.test/a", { tag: ["a", "b"] })).toBe(
      "https://x.test/a?tag=a&tag=b",
    )
  })

  it("reproduces a bare flag value-less", () => {
    expect(urlMergingParams("https://x.test/a", { debug: null })).toBe("https://x.test/a?debug")
  })

  it("percent-encodes to RFC 3986 unreserved, so a value survives the trip", () => {
    const merged = urlMergingParams("https://x.test/a", { q: "a&b=c d" })
    expect(merged).toBe("https://x.test/a?q=a%26b%3Dc%20d")
  })

  it("encodes the characters encodeURIComponent leaves alone", () => {
    // `!'()*` are reserved in RFC 3986 but not escaped by encodeURIComponent,
    // and a param carrying one has to come back as it went.
    expect(urlMergingParams("https://x.test/a", { q: "a!b'c(d)e*f" })).toBe(
      "https://x.test/a?q=a%21b%27c%28d%29e%2Af",
    )
  })

  it("leaves the url alone when there are no params", () => {
    // Absence is the case under test.
    // oxlint-disable-next-line unicorn/no-useless-undefined
    expect(urlMergingParams("https://x.test/a", undefined)).toBe("https://x.test/a")
    expect(urlMergingParams("https://x.test/a", {})).toBe("https://x.test/a")
    expect(urlMergingParams("https://x.test/a", "not an object")).toBe("https://x.test/a")
  })

  it("survives a malformed escape in the existing query", () => {
    // `decodeURIComponent` throws on a lone `%`; the raw spelling still counts.
    expect(urlMergingParams("https://x.test/a?bad=%zz", { page: 1 })).toBe(
      "https://x.test/a?bad=%zz&page=1",
    )
  })
})
