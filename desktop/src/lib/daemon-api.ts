/**
 * The API Testing calls.
 *
 * Its own module rather than more of `daemon.ts`, which is at the line budget
 * that made the settings and command calls separate files. Re-exported from
 * `@/lib/daemon`, which stays the one import for everything that talks to the
 * daemon.
 *
 * Everything here is something a webview cannot do for itself: send a request
 * without the browser's CORS opinion (and see the redirect chain, the TLS
 * timing and the `Set-Cookie` it would otherwise be forbidden to read),
 * generate code, parse a cURL line, and read or write a Postman file.
 */

import { invoke } from "@tauri-apps/api/core"
import type { CodeTargetName } from "@/lib/api/labels"
import type {
  ApiClientData,
  ApiCollection,
  ApiEnvironment,
  AuthSpec,
  SavedRequest,
} from "@/lib/api/model"
import type { VariableScope } from "@/lib/api/variables"

/** One `Set-Cookie` this response carried, already parsed. */
export interface ResponseCookie {
  name: string
  value: string
  domain: string
  path: string
  expires: string
  maxAge: string
  httpOnly: boolean
  secure: boolean
  sameSite: string
}

/**
 * A phase is absent rather than zero when the platform did not measure it —
 * off-Darwin there are no URLSession metrics at all, so only `total` is ever
 * filled in. `undefined` is what an omitted one arrives as; the pane treats
 * both as "not measured".
 */
export interface ResponseTiming {
  dns?: number | null
  connect?: number | null
  tls?: number | null
  firstByte?: number | null
  total: number
}

export interface RedirectHop {
  statusCode: number
  from: string
  to: string
}

export interface AssertionOutcomeWire {
  id: string
  label: string
  passed: boolean
  detail: string
}

/**
 * One send's answer.
 *
 * The body arrives in whichever form is usable: `bodyText` and `prettyBody`
 * for anything textual — those are exactly the pane's Raw and Pretty, so
 * nothing is sent twice — and `bodyBase64` only for an image or a binary,
 * where the bytes themselves are the content. `bodyOmitted` covers the third
 * case, a binary too large to inline, which must not read as an empty body.
 */
export interface ApiSendResponse {
  statusCode: number
  statusText: string
  headers: { key: string; value: string }[]
  cookies: ResponseCookie[]
  bodyText: string | null
  prettyBody: string | null
  bodyBase64: string | null
  bodyOmitted: boolean
  format: "json" | "xml" | "html" | "text" | "image" | "binary"
  mediaType: string
  elapsedMs: number
  size: number
  sizeText: string
  truncated: boolean
  redirects: RedirectHop[]
  timing: ResponseTiming | null
  finalURL: string
  sentBytes: number
  preparedURL: string
  assertions: AssertionOutcomeWire[]
  warnings: string[]
}

/** The saved workspace — the Mac's own `api-client.json`. */
export function apiWorkspace(): Promise<{ data: ApiClientData }> {
  return invoke("api_workspace")
}

/** Replaces the whole document; answers with what landed. */
export function apiWrite(data: ApiClientData): Promise<{ data: ApiClientData }> {
  return invoke("api_write", { data })
}

export function apiSend(request: {
  request: SavedRequest
  scope: VariableScope
  inheritedAuth: AuthSpec | null
  /** A handle for `apiCancel`; omitted by the collection runner. */
  sendId?: string
}): Promise<ApiSendResponse> {
  return invoke<RawSendResponse>("api_send", { request }).then(normaliseSendResponse)
}

/**
 * What the wire actually carries.
 *
 * Swift's `JSONEncoder` *omits* a nil optional rather than writing `null`, so
 * every field the daemon left empty arrives as `undefined`. That matters more
 * than it looks: a `!== null` test passes for `undefined`, which is how a
 * missing body becomes `data:image/png;base64,undefined` on screen. The rest
 * of this app reads a fully-populated `ApiSendResponse`, so the widening stops
 * here — one place, rather than a `??` at every use.
 */
type RawSendResponse = {
  [Key in keyof ApiSendResponse]: ApiSendResponse[Key] | undefined
}

export function normaliseSendResponse(raw: RawSendResponse): ApiSendResponse {
  return {
    statusCode: raw.statusCode ?? 0,
    statusText: raw.statusText ?? "",
    headers: raw.headers ?? [],
    cookies: raw.cookies ?? [],
    bodyText: raw.bodyText ?? null,
    prettyBody: raw.prettyBody ?? null,
    bodyBase64: raw.bodyBase64 ?? null,
    bodyOmitted: raw.bodyOmitted ?? false,
    format: raw.format ?? "text",
    mediaType: raw.mediaType ?? "",
    elapsedMs: raw.elapsedMs ?? 0,
    size: raw.size ?? 0,
    sizeText: raw.sizeText ?? "0 B",
    truncated: raw.truncated ?? false,
    redirects: raw.redirects ?? [],
    timing: raw.timing ?? null,
    finalURL: raw.finalURL ?? "",
    sentBytes: raw.sentBytes ?? 0,
    preparedURL: raw.preparedURL ?? "",
    assertions: raw.assertions ?? [],
    warnings: raw.warnings ?? [],
  }
}

/**
 * Stops an in-flight send.
 *
 * A real cancel: the daemon tears the request down, rather than this side
 * dropping an answer that is still on its way. `cancelled: false` is the
 * ordinary race — the send finished first — and not a failure.
 */
export function apiCancel(sendId: string): Promise<{ cancelled: boolean }> {
  return invoke("api_cancel", { sendId })
}

export function apiCode(request: {
  request: SavedRequest
  scope: VariableScope
  inheritedAuth: AuthSpec | null
  target: CodeTargetName
}): Promise<{ code: string }> {
  return invoke("api_code", { request })
}

/** Parses a pasted cURL command line, or refuses it. */
export function apiCurl(text: string): Promise<{ request: SavedRequest; warnings: string[] }> {
  return invoke("api_curl", { text })
}

/** Reads a Postman file, with fresh ids already applied by the daemon. */
export function apiImport(path: string): Promise<{
  collections: ApiCollection[]
  environments: ApiEnvironment[]
  summary: string
  warnings: string[]
}> {
  return invoke("api_import", { path })
}

/**
 * Builds an export's JSON and the name to offer for it.
 *
 * The file is written by `exportText`, into the same folder every other export
 * here lands in — two places deciding that is how a Show in folder button ends
 * up pointing at the wrong one.
 */
export function apiExport(
  payload:
    | { kind: "collection"; collection: ApiCollection }
    | { kind: "environment"; environment: ApiEnvironment }
    | { kind: "workspace"; workspace: ApiClientData },
  includeSecrets = false,
): Promise<{ json: string; suggestedName: string }> {
  return invoke("api_export", { request: { payload, includeSecrets } })
}
