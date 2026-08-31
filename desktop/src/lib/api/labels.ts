/**
 * The words and colours the API pane shows, taken from the Mac's own views.
 *
 * Split out of `model.ts` rather than living beside the types: these are
 * presentation, and the model is the document. Every string here has a
 * counterpart in `ApiLabels`, `ApiStatusStyle` or `ApiAssertionRow`, and a
 * difference is a difference someone moving between the two apps has to
 * relearn.
 */

import type {
  AssertionOperatorName,
  AssertionTarget,
  AuthType,
  BodyType,
  HttpMethod,
} from "@/lib/api/model"

export function bodyLabel(type: BodyType): string {
  switch (type) {
    case "none":
      return "None"
    case "json":
      return "JSON"
    case "formUrlEncoded":
      return "Form"
    case "multipart":
      return "Form Data"
    case "raw":
      return "Raw"
    case "graphql":
      return "GraphQL"
    case "binary":
      return "Binary"
  }
}

export function authLabel(type: AuthType): string {
  switch (type) {
    case "none":
      return "None"
    case "bearer":
      return "Bearer"
    case "basic":
      return "Basic"
    case "apiKey":
      return "API Key"
    case "oauth2":
      return "OAuth 2"
  }
}

export const ASSERTION_KINDS: { value: AssertionTarget["kind"]; label: string }[] = [
  { value: "statusCode", label: "Status code" },
  { value: "responseTimeMs", label: "Response time" },
  { value: "bodySize", label: "Body size" },
  { value: "bodyText", label: "Body text" },
  { value: "header", label: "Header" },
  { value: "jsonPath", label: "JSON path" },
]

export const ASSERTION_OPERATORS: { value: AssertionOperatorName; label: string }[] = [
  { value: "equals", label: "equals" },
  { value: "notEquals", label: "does not equal" },
  { value: "contains", label: "contains" },
  { value: "notContains", label: "does not contain" },
  { value: "matchesRegex", label: "matches regex" },
  { value: "lessThan", label: "is less than" },
  { value: "greaterThan", label: "is greater than" },
  { value: "exists", label: "exists" },
  { value: "notExists", label: "does not exist" },
  { value: "isEmpty", label: "is empty" },
  { value: "isNotEmpty", label: "is not empty" },
]

/** Operators that take no expected value — `AssertionOperator.isUnary`. */
export function isUnary(op: AssertionOperatorName): boolean {
  return op === "exists" || op === "notExists" || op === "isEmpty" || op === "isNotEmpty"
}

export type CodeTargetName =
  | "curl"
  | "httpie"
  | "fetch"
  | "axios"
  | "pythonRequests"
  | "swiftURLSession"

export const CODE_TARGETS: { value: CodeTargetName; label: string }[] = [
  { value: "curl", label: "cURL" },
  { value: "httpie", label: "HTTPie" },
  { value: "fetch", label: "JavaScript · fetch" },
  { value: "axios", label: "Node · axios" },
  { value: "pythonRequests", label: "Python · requests" },
  { value: "swiftURLSession", label: "Swift · URLSession" },
]

/**
 * The method's colour, as `ApiStatusStyle.color(for:)` picks it.
 *
 * Tailwind classes rather than the theme tokens: these are SwiftUI's own
 * semantic colours on the Mac (`.green`, `.orange`, …) and there is no token
 * for "the colour DELETE is".
 */
export function methodColor(method: HttpMethod): string {
  switch (method) {
    case "GET":
      return "text-green-400"
    case "POST":
      return "text-orange-400"
    case "PUT":
      return "text-blue-400"
    case "PATCH":
      return "text-purple-400"
    case "DELETE":
      return "text-red-400"
    case "HEAD":
      return "text-cyan-400"
    case "OPTIONS":
      return "text-neutral-400"
  }
}

/** The status code's colour, as `ApiStatusStyle.color(for:)` picks it. */
export function statusColor(code: number): string {
  if (code >= 200 && code < 300) return "text-green-400"
  if (code >= 300 && code < 400) return "text-yellow-400"
  if (code >= 400 && code < 500) return "text-orange-400"
  if (code >= 500) return "text-red-400"
  return "text-text-primary"
}

/** `ApiResponse.formatBytes`, to its four steps and its two precisions. */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1_048_576) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1_073_741_824) return `${(bytes / 1_048_576).toFixed(1)} MB`
  return `${(bytes / 1_073_741_824).toFixed(2)} GB`
}
