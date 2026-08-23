/**
 * A copy-pasteable `curl` that reproduces a Reactotron-captured API request.
 *
 * A port of ADBKit's `ReactotronCurl`, decision for decision. It is the one
 * thing in the timeline someone takes *out* of the app and runs, so a command
 * that reproduces something other than what the app sent is worse than no
 * button at all — which is why each of the four repairs below is here rather
 * than left to the reader to notice.
 */

import { compactJson, isJsonObject, type JsonValue } from "@/lib/json"

/**
 * Wraps a value for `sh`, the way ADBKit's `shellQuote` does: single quotes,
 * with any embedded quote closed, escaped and reopened.
 */
export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", String.raw`'\''`)}'`
}

/** The text of a value as a header or a body carries it. */
function rendered(value: JsonValue): string {
  return typeof value === "string" ? value : compactJson(value)
}

export function curlCommand(args: {
  method: string
  url: string
  request?: JsonValue | undefined
}): string {
  const verb = args.method.toUpperCase()
  const fullUrl = urlMergingParams(args.url, field(args.request, "params"))
  const form = formParts(field(args.request, "data"))
  const body = form === null ? requestBody(args.request) : null
  const parts = ["curl"]
  // `curl` switches to POST the moment a body is present, so the verb has to be
  // stated whenever this is not a plain body-less GET — otherwise copying a GET
  // that carries a body silently produces a POST.
  if (verb !== "GET" || body !== null || form !== null) parts.push(`-X ${verb}`)
  parts.push(shellQuote(fullUrl))

  const headers = field(args.request, "headers")
  if (headers !== undefined && isJsonObject(headers)) {
    for (const key of Object.keys(headers).toSorted()) {
      // A multipart body is rebuilt as --form-string fields below, so the
      // captured content-type's boundary is stale — curl must mint its own.
      if (form !== null && key.toLowerCase() === "content-type") continue
      parts.push(`-H ${shellQuote(`${key}: ${rendered(headers[key] ?? null)}`)}`)
    }
  }
  for (const part of form ?? []) {
    // --form-string, not -F: a value starting with "@" or "<" would otherwise
    // be read as a local file or stdin reference.
    parts.push(`--form-string ${shellQuote(`${part.name}=${part.value}`)}`)
  }
  if (body !== null) parts.push(`--data ${shellQuote(body)}`)
  return parts.join(" \\\n  ")
}

function field(value: JsonValue | undefined, key: string): JsonValue | undefined {
  if (value === undefined || !isJsonObject(value)) return undefined
  return value[key]
}

/**
 * The body to send, or null when the request carries nothing meaningful — JSON
 * null, an empty string, an empty `{}` or `[]`. Keeps a body-less GET body-less,
 * and therefore a GET rather than a POST curl inferred.
 */
function requestBody(request: JsonValue | undefined): string | null {
  const data = field(request, "data")
  if (data === undefined || data === null) return null
  const text = rendered(data)
  return text === "" || text === "{}" || text === "[]" || text === "null" ? null : text
}

/**
 * The networking plugin reports `url` from `xhr.responseURL` — the *final* URL
 * after any redirect or gateway rewrite, which can arrive without the query
 * string the app actually sent — while the original params ride separately in
 * the payload's `params`. Append every param the URL does not already carry, so
 * the copied command reproduces the request. When the URL kept its query this
 * is a no-op.
 */
export function urlMergingParams(url: string, params: JsonValue | undefined): string {
  if (params === undefined || !isJsonObject(params)) return url
  const keys = Object.keys(params)
  if (keys.length === 0) return url
  const existing = existingQueryKeys(url)
  let merged = url
  for (const key of keys.toSorted()) {
    if (existing.has(key)) continue
    const value = params[key] ?? null
    // A repeated key (?tag=a&tag=b) arrives from query-string as an array.
    for (const item of Array.isArray(value) ? value : [value]) {
      const separator = merged.includes("?") ? "&" : "?"
      // A bare flag (?debug) parses to null — reproduce it value-less.
      merged +=
        item === null
          ? `${separator}${queryEscape(key)}`
          : `${separator}${queryEscape(key)}=${queryEscape(rendered(item))}`
    }
  }
  return merged
}

/**
 * The query keys already in `url`, in both their raw and percent-decoded
 * spellings — the client decodes some param keys and not others depending on
 * its version, so either form has to match.
 */
function existingQueryKeys(url: string): Set<string> {
  const mark = url.indexOf("?")
  if (mark < 0) return new Set()
  const keys = new Set<string>()
  for (const pair of url.slice(mark + 1).split("&")) {
    // A degenerate pair like "=" splits to an empty key — skip it.
    const key = pair.split("=")[0] ?? ""
    if (key === "") continue
    keys.add(key)
    try {
      keys.add(decodeURIComponent(key))
    } catch {
      // A malformed escape is not a second spelling; the raw form stands.
    }
  }
  return keys
}

/**
 * RFC 3986 unreserved characters only — everything else is percent-encoded, so a
 * param carrying `&`, `=` or a space survives the round trip.
 *
 * `encodeURIComponent` leaves `!'()*` alone, which is a smaller set than the
 * unreserved one, so those four are finished by hand.
 */
function queryEscape(value: string): string {
  return encodeURIComponent(value).replaceAll(
    /[!'()*]/gu,
    (character) => `%${character.codePointAt(0)?.toString(16).toUpperCase() ?? ""}`,
  )
}

/**
 * React Native's `FormData` reaches the wire as `{"_parts": [[name, value], …]}`
 * — attaching that JSON as `--data` reproduces nothing. Rebuild it as form
 * fields instead: string values pass through, and a file part (an object with
 * `uri`/`name`/`type`) renders as its JSON, since the file itself lives on the
 * device and cannot ride a copied command.
 */
export function formParts(data: JsonValue | undefined): { name: string; value: string }[] | null {
  if (data === undefined || !isJsonObject(data)) return null
  const keys = Object.keys(data)
  if (keys.length !== 1) return null
  const parts = data["_parts"]
  if (!Array.isArray(parts) || parts.length === 0) return null
  const fields: { name: string; value: string }[] = []
  for (const part of parts) {
    if (!Array.isArray(part) || part.length < 2) return null
    fields.push({ name: rendered(part[0] ?? null), value: rendered(part[1] ?? null) })
  }
  return fields
}
