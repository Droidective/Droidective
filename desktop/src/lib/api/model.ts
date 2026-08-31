/**
 * The API Testing document, as `ADBKit/Services/ApiClient/ApiModels.swift`
 * holds it.
 *
 * The daemon serves and stores this shape verbatim — it is the Mac's own
 * `api-client.json` — so these types are a transcription rather than a wire
 * format of their own. Anything added on the Swift side has to appear here to
 * be editable, and anything this side invents would be dropped by the store's
 * lenient decoder without a word.
 *
 * Only the *editing* lives on this side. Sending, code generation, cURL
 * parsing and Postman interchange are daemon routes, because they are the four
 * things a webview genuinely cannot do for itself.
 */

export type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD" | "OPTIONS"

export const HTTP_METHODS: HttpMethod[] = [
  "GET",
  "POST",
  "PUT",
  "PATCH",
  "DELETE",
  "HEAD",
  "OPTIONS",
]

export interface ApiKeyValue {
  id: string
  key: string
  value: string
  enabled: boolean
  /** Postman's `description`, renamed as it is in Swift. */
  note: string
}

export type FormFieldKind = "text" | "file"

export interface ApiFormField {
  id: string
  key: string
  /** Text for `text`, an absolute host path for `file`. */
  value: string
  kind: FormFieldKind
  /** Explicit part Content-Type; empty lets the builder decide. */
  contentType: string
  enabled: boolean
}

export type BodyType =
  | "none"
  | "json"
  | "formUrlEncoded"
  | "multipart"
  | "raw"
  | "graphql"
  | "binary"

export const BODY_TYPES: BodyType[] = [
  "none",
  "json",
  "formUrlEncoded",
  "multipart",
  "raw",
  "graphql",
  "binary",
]

export type RawLanguage = "text" | "json" | "xml" | "html" | "javascript"

export const RAW_LANGUAGES: RawLanguage[] = ["text", "json", "xml", "html", "javascript"]

/** The Content-Type a raw body's syntax implies, as `RawLanguage` does. */
export function rawContentType(language: RawLanguage): string {
  switch (language) {
    case "text":
      return "text/plain"
    case "json":
      return "application/json"
    case "xml":
      return "application/xml"
    case "html":
      return "text/html"
    case "javascript":
      return "application/javascript"
  }
}

export interface RequestBodySpec {
  type: BodyType
  jsonText: string
  rawText: string
  rawLanguage: RawLanguage
  rawContentType: string
  formFields: ApiKeyValue[]
  multipartFields: ApiFormField[]
  graphqlQuery: string
  graphqlVariables: string
  binaryFilePath: string
}

export type AuthType = "none" | "bearer" | "basic" | "apiKey" | "oauth2"

export const AUTH_TYPES: AuthType[] = ["none", "bearer", "basic", "apiKey", "oauth2"]

export type ApiKeyLocation = "header" | "query"

export interface AuthSpec {
  type: AuthType
  bearerToken: string
  basicUsername: string
  basicPassword: string
  apiKeyName: string
  apiKeyValue: string
  apiKeyLocation: ApiKeyLocation
  /** An already-obtained token — Droidective runs no OAuth grant flow. */
  oauth2Token: string
  oauth2HeaderPrefix: string
}

export interface RequestSettings {
  /** Seconds; 0 waits as long as the server takes, capped daemon-side. */
  timeoutSeconds: number
  followRedirects: boolean
  maxRedirects: number
  /** Off skips TLS chain and hostname checks for this request. */
  validateTLS: boolean
  sendCookies: boolean
  maxResponseBytes: number
}

export type AssertionOperatorName =
  | "equals"
  | "notEquals"
  | "contains"
  | "notContains"
  | "matchesRegex"
  | "lessThan"
  | "greaterThan"
  | "exists"
  | "notExists"
  | "isEmpty"
  | "isNotEmpty"

/**
 * What an assertion looks at.
 *
 * Encoded as `{kind, argument}` because that is how `AssertionTarget` encodes
 * itself: an enum with two associated-value cases, flattened to a name and the
 * header or JSON path it carries.
 */
export interface AssertionTarget {
  kind: "statusCode" | "responseTimeMs" | "bodySize" | "bodyText" | "header" | "jsonPath"
  argument: string
}

export interface ApiAssertion {
  id: string
  enabled: boolean
  target: AssertionTarget
  op: AssertionOperatorName
  expected: string
}

export interface SavedRequest {
  id: string
  name: string
  note: string
  method: HttpMethod
  url: string
  headers: ApiKeyValue[]
  queryParams: ApiKeyValue[]
  /** Values for `:name` placeholders in the path. */
  pathVariables: ApiKeyValue[]
  body: RequestBodySpec
  auth: AuthSpec
  settings: RequestSettings
  assertions: ApiAssertion[]
  createdAt: number
  modifiedAt: number
}

export interface ApiFolder {
  id: string
  name: string
  note: string
  items: ApiItem[]
}

/**
 * One node of a collection.
 *
 * The explicit `kind` tag is the on-disk shape, not a convenience: `ApiItem`
 * encodes itself that way so the file stays readable, and a node written
 * without it would be sniffed rather than read.
 */
export type ApiItem =
  | { kind: "request"; request: SavedRequest }
  | { kind: "folder"; folder: ApiFolder }

export function itemId(item: ApiItem): string {
  return item.kind === "request" ? item.request.id : item.folder.id
}

export function itemName(item: ApiItem): string {
  return item.kind === "request" ? item.request.name : item.folder.name
}

export interface ApiCollection {
  id: string
  name: string
  note: string
  items: ApiItem[]
  /** Beats the environment, loses to request-local. */
  variables: ApiKeyValue[]
  /** Applied to requests whose own auth is `none`. */
  auth: AuthSpec
  createdAt: number
}

export interface ApiEnvironment {
  id: string
  name: string
  variables: ApiKeyValue[]
}

export interface ApiHistoryEntry {
  id: string
  method: HttpMethod
  /** The resolved URL that went on the wire. */
  url: string
  statusCode?: number | null
  errorText?: string | null
  elapsedMs?: number | null
  responseSize?: number | null
  timestamp: number
  /** Secret-free copy — see `withoutSecrets`. */
  request: SavedRequest
}

export interface ApiClientData {
  collections: ApiCollection[]
  environments: ApiEnvironment[]
  activeEnvironmentId: string | null
  globals: ApiKeyValue[]
  history: ApiHistoryEntry[]
}
