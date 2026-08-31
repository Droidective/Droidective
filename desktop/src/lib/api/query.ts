/**
 * The URL's query string and its `:name` path segments —
 * `ApiQueryString.swift` plus the path-variable scan `ApiRequestEditor` does
 * inline, ported.
 *
 * The URL bar and the Params table are deliberately *not* kept in lockstep:
 * the builder merges the table on top of whatever the URL already carries, so
 * a silent two-way sync would be a good way to lose a parameter. This is the
 * explicit extraction the Params tab offers instead.
 */

import { newKeyValue } from "@/lib/api/defaults"
import type { ApiKeyValue } from "@/lib/api/model"

interface UrlParts {
  base: string
  query: string
  fragment: string
}

/** `HttpRequestBuilder.split` — fragment first, then query. */
export function splitUrl(url: string): UrlParts {
  let rest = url
  let fragment = ""
  const hash = rest.indexOf("#")
  if (hash >= 0) {
    fragment = rest.slice(hash + 1)
    rest = rest.slice(0, hash)
  }
  let query = ""
  const mark = rest.indexOf("?")
  if (mark >= 0) {
    query = rest.slice(mark + 1)
    rest = rest.slice(0, mark)
  }
  return { base: rest, query, fragment }
}

export function hasQuery(url: string): boolean {
  return splitUrl(url).query !== ""
}

/**
 * The parameters in a URL's query string, in the order they appear.
 *
 * A bare `?flag` with no `=` becomes a parameter with an empty value, which is
 * how servers read it.
 */
export function queryParameters(url: string): ApiKeyValue[] {
  const { query } = splitUrl(url)
  if (query === "") return []
  const found: ApiKeyValue[] = []
  for (const pair of query.split("&")) {
    if (pair === "") continue
    const separator = pair.indexOf("=")
    if (separator < 0) {
      found.push(newKeyValue(decode(pair), ""))
      continue
    }
    const name = decode(pair.slice(0, separator))
    if (name === "") continue
    found.push(newKeyValue(name, decode(pair.slice(separator + 1))))
  }
  return found
}

/**
 * The same URL with its query removed, fragment kept. Pairs with
 * `queryParameters`: extract into the table, strip from the bar, and the
 * request the builder produces is unchanged.
 */
export function removingQuery(url: string): string {
  const parts = splitUrl(url)
  if (parts.query === "") return url
  return parts.fragment === "" ? parts.base : `${parts.base}#${parts.fragment}`
}

/**
 * The `:name` placeholders in the URL's *path*.
 *
 * The host is skipped deliberately, so `localhost:3000` is never mistaken for
 * a variable — the same rule `substitutePathVariables` follows when the
 * request is actually built.
 */
export function pathVariableNames(url: string): string[] {
  const base = url.split("?")[0] ?? ""
  const schemeEnd = base.indexOf("://")
  if (schemeEnd < 0) return []
  const afterScheme = base.slice(schemeEnd + 3)
  const firstSlash = afterScheme.indexOf("/")
  if (firstSlash < 0) return []
  return afterScheme
    .slice(firstSlash)
    .split("/")
    .filter((segment) => segment.startsWith(":") && segment.length > 1)
    .map((segment) => segment.slice(1))
}

/**
 * `+` is a space and `%xx` is a byte, as `removingPercentEncoding` reads them.
 *
 * A malformed escape decodes to itself rather than throwing: someone pasting a
 * URL with a stray `%` should get their URL back, not an empty table.
 */
function decode(text: string): string {
  const plus = text.replaceAll("+", " ")
  try {
    return decodeURIComponent(plus)
  } catch {
    return plus
  }
}
