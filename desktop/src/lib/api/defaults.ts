/**
 * Fresh values for the API Testing document.
 *
 * Split from `model.ts` so the types stay a transcription of
 * `ApiModels.swift` and nothing else. Every default here is that file's own
 * `init` default — a request that starts as a POST here and a GET there is a
 * difference someone would have to notice.
 */

import type {
  ApiClientData,
  ApiCollection,
  ApiEnvironment,
  ApiFolder,
  ApiFormField,
  ApiKeyValue,
  ApiAssertion,
  AuthSpec,
  RequestBodySpec,
  RequestSettings,
  SavedRequest,
} from "@/lib/api/model"

/** `ApiClientData.historyLimit`. */
export const HISTORY_LIMIT = 200

/**
 * A fresh identifier.
 *
 * `crypto.randomUUID` is not guaranteed outside a secure context and this page
 * is served over a custom protocol, so the fallback is not decoration — a
 * `randomUUID` that is undefined would throw on the first new row someone
 * added. `getRandomValues` is available everywhere the app runs.
 */
export function newId(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID()
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  // RFC 4122 version 4, so an id written here is indistinguishable from one
  // the Swift side wrote.
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x40
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("")
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

function now(): number {
  return Date.now() / 1000
}

export function newKeyValue(key = "", value = ""): ApiKeyValue {
  return { id: newId(), key, value, enabled: true, note: "" }
}

export function newFormField(): ApiFormField {
  return { id: newId(), key: "", value: "", kind: "text", contentType: "", enabled: true }
}

export function newBody(): RequestBodySpec {
  return {
    type: "none",
    jsonText: "",
    rawText: "",
    rawLanguage: "text",
    rawContentType: "",
    formFields: [],
    multipartFields: [],
    graphqlQuery: "",
    graphqlVariables: "",
    binaryFilePath: "",
  }
}

export function newAuth(): AuthSpec {
  return {
    type: "none",
    bearerToken: "",
    basicUsername: "",
    basicPassword: "",
    apiKeyName: "",
    apiKeyValue: "",
    apiKeyLocation: "header",
    oauth2Token: "",
    oauth2HeaderPrefix: "Bearer",
  }
}

export function newSettings(): RequestSettings {
  return {
    timeoutSeconds: 60,
    followRedirects: true,
    maxRedirects: 10,
    validateTLS: true,
    sendCookies: true,
    maxResponseBytes: 32 * 1024 * 1024,
  }
}

export function newRequest(): SavedRequest {
  const stamp = now()
  return {
    id: newId(),
    name: "Untitled Request",
    note: "",
    method: "GET",
    url: "",
    headers: [],
    queryParams: [],
    pathVariables: [],
    body: newBody(),
    auth: newAuth(),
    settings: newSettings(),
    assertions: [],
    createdAt: stamp,
    modifiedAt: stamp,
  }
}

export function newAssertion(): ApiAssertion {
  return {
    id: newId(),
    enabled: true,
    target: { kind: "statusCode", argument: "" },
    op: "equals",
    expected: "",
  }
}

export function newCollection(name: string): ApiCollection {
  return {
    id: newId(),
    name,
    note: "",
    items: [],
    variables: [],
    auth: newAuth(),
    createdAt: now(),
  }
}

export function newFolder(name: string): ApiFolder {
  return { id: newId(), name, note: "", items: [] }
}

export function newEnvironment(name: string): ApiEnvironment {
  return { id: newId(), name, variables: [] }
}

export function emptyWorkspace(): ApiClientData {
  return { collections: [], environments: [], activeEnvironmentId: null, globals: [], history: [] }
}

/**
 * Header names whose value is masked before a request reaches history or an
 * export. The list is `SavedRequest.secretHeaderNames`, verbatim — a name that
 * is on one side and not the other is a credential written to disk.
 */
const SECRET_HEADER_NAMES = new Set([
  "authorization",
  "proxy-authorization",
  "cookie",
  "set-cookie",
  "x-api-key",
  "api-key",
  "apikey",
  "x-auth-token",
  "x-access-token",
  "x-csrf-token",
  "x-session-token",
])

export function authWithoutSecrets(auth: AuthSpec): AuthSpec {
  return { ...auth, bearerToken: "", basicPassword: "", apiKeyValue: "", oauth2Token: "" }
}

/**
 * A copy safe to keep in history: auth secrets blanked, credential headers
 * masked. The URL survives — it is what makes history navigable.
 */
export function requestWithoutSecrets(request: SavedRequest): SavedRequest {
  return {
    ...request,
    auth: authWithoutSecrets(request.auth),
    headers: request.headers.map((header) =>
      SECRET_HEADER_NAMES.has(header.key.toLowerCase())
        ? { ...header, value: header.value === "" ? "" : "•••" }
        : header,
    ),
  }
}

/** Enabled pairs with a key, last one winning — `activeMap` in Swift. */
export function activeMap(pairs: ApiKeyValue[]): Record<string, string> {
  const map: Record<string, string> = {}
  for (const pair of pairs) {
    if (pair.enabled && pair.key !== "") map[pair.key] = pair.value
  }
  return map
}
