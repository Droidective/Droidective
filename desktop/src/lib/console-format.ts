/**
 * How a CDP value is rendered in the console — a port of ADBKit's
 * `RemoteObjectDisplay`, rule for rule.
 *
 * The rules are Chrome's, not ours, and they are tuned to how **Hermes** (not
 * V8) serialises: `bigint` arrives as `type: ""`, `-0`/`Infinity`/`NaN` as
 * `unserializableValue` with no `value`, and `Date`/`Map`/`Set`/`RegExp` as
 * plain `"Object"` because Hermes does not tag those subtypes. Porting them
 * loosely would give the two apps different consoles for the same log line.
 */

import type { ObjectPreview, PropertyPreview, RemoteObject } from "@/lib/cdp"

/** A colourable span. Semantic, so the markup decides the colour. */
export type TokenKind =
  | "string"
  | "number"
  | "boolean"
  | "null"
  | "undefined"
  | "function"
  | "symbol"
  | "key"
  | "className"
  | "punctuation"
  | "plain"

export interface Token {
  text: string
  kind: TokenKind
}

/**
 * Where a value is being rendered, which is what decides whether a string is
 * quoted. Chrome prints a *top-level* `console.log` string argument bare
 * (`console.log('hi')` → `hi`, newlines and all) and quotes strings everywhere
 * else — nested in a preview, or returned from the prompt.
 */
export type RenderStyle = "value" | "consoleArgument"

function token(text: string, kind: TokenKind): Token {
  return { text, kind }
}

/**
 * Chrome's string literal: single quotes, switching to double when the text
 * already contains a single one, with the escapes a one-line preview needs so
 * a logged multi-line string cannot break the row into several.
 */
export function quoted(text: string): string {
  let escaped = text
    .replaceAll("\\", "\\\\")
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r")
    .replaceAll("\t", "\\t")
  if (escaped.includes("'") && !escaped.includes('"')) return `"${escaped}"`
  escaped = escaped.replaceAll("'", "\\'")
  return `'${escaped}'`
}

/** "function adder(a0, a1) { [bytecode] }" → "ƒ adder(a0, a1)". */
export function functionSummary(description: string | undefined): string {
  if (description === undefined || description === "") return "ƒ ()"
  const head = description.split("{")[0] ?? description
  const trimmed = head.trim()
  const body = trimmed.startsWith("function ") ? trimmed.slice("function ".length) : trimmed
  return body === "" ? "ƒ ()" : `ƒ ${body}`
}

/** Plain rendering of a primitive carried in `RemoteObject.value`. */
export function displayString(value: unknown): string {
  if (value === null) return "null"
  if (typeof value === "number") {
    // Guards the Int(NaN/Infinity) trap the Swift version calls out.
    return Number.isFinite(value) && Number.isInteger(value) ? String(value) : String(value)
  }
  if (typeof value === "boolean") return String(value)
  if (typeof value === "string") return value
  return JSON.stringify(value) ?? ""
}

function numberString(object: RemoteObject): string {
  // -0 / Infinity / NaN come back via description or unserializableValue.
  if (object.description !== undefined) return object.description
  if (object.value !== undefined) return displayString(object.value)
  return object.unserializableValue ?? "0"
}

/** The element count out of an array preview's `Array(n)` description. */
function arrayLength(preview: ObjectPreview): number | null {
  const description = preview.description
  if (description === undefined) return null
  if (!description.startsWith("Array(") || !description.endsWith(")")) return null
  const inner = description.slice("Array(".length, -1)
  const count = Math.trunc(Number(inner))
  return Number.isNaN(count) ? null : count
}

function elementToken(property: PropertyPreview): Token {
  switch (property.type) {
    case "string":
      return token(quoted(property.value ?? ""), "string")
    case "number":
    case "bigint":
      return token(property.value ?? "", "number")
    case "boolean":
      return token(property.value ?? "", "boolean")
    case "undefined":
      return token("undefined", "undefined")
    case "symbol":
      return token(property.value ?? "Symbol()", "symbol")
    case "function":
      return token("ƒ", "function")
    case "object":
      if (property.subtype === "null") return token("null", "null")
      // `Array(3)`, or a class name — Chrome shows both verbatim. A plain
      // nested object is Chrome's `{…}`, not the word "Object".
      if (property.value !== undefined && property.value !== "Object") {
        return token(property.value, "className")
      }
      return token("{…}", "punctuation")
    default:
      return token(property.value ?? "", "plain")
  }
}

export function previewTokens(preview: ObjectPreview): Token[] {
  if (preview.subtype === "array" || preview.description?.startsWith("Array(") === true) {
    const tokens: Token[] = []
    // Chrome leads a multi-element array with its length — `(3) [1, 2, 3]` —
    // and leaves `[]` and `[x]` to speak for themselves.
    const count = arrayLength(preview)
    if (count !== null && count > 1) tokens.push(token(`(${String(count)}) `, "className"))
    tokens.push(token("[", "punctuation"))
    preview.properties.forEach((property, index) => {
      if (index > 0) tokens.push(token(", ", "punctuation"))
      tokens.push(elementToken(property))
    })
    if (preview.overflow) tokens.push(token(", …", "punctuation"))
    tokens.push(token("]", "punctuation"))
    return tokens
  }
  if (preview.subtype === "error") {
    return [token(preview.description ?? "Error", "plain")]
  }
  const tokens: Token[] = []
  const className = preview.description ?? ""
  if (className !== "" && className !== "Object") tokens.push(token(`${className} `, "className"))
  tokens.push(token("{", "punctuation"))
  preview.properties.forEach((property, index) => {
    if (index > 0) tokens.push(token(", ", "punctuation"))
    tokens.push(token(property.name, "key"), token(": ", "punctuation"), elementToken(property))
  })
  if (preview.overflow) tokens.push(token(", …", "punctuation"))
  tokens.push(token("}", "punctuation"))
  return tokens
}

function objectTokens(object: RemoteObject): Token[] {
  if (object.subtype === "null") return [token("null", "null")]
  if (object.subtype === "error") {
    const message = object.description?.split("\n")[0] ?? "Error"
    return [token(message, "plain")]
  }
  if (object.preview !== undefined) return previewTokens(object.preview)
  // No preview: Hermes replays its buffered console history without one, so the
  // whole pre-connect backlog lands here. `Array(2)` or a class name still says
  // something; the bare word "Object" says less than Chrome's `{…}`, which
  // reads as "open me".
  if (object.description !== undefined && object.description !== "Object") {
    return [token(object.description, "className")]
  }
  if (object.className !== undefined && object.className !== "Object") {
    return [token(object.className, "className")]
  }
  return [token("{…}", "punctuation")]
}

/** The compact one-line rendering as colourable tokens. */
export function tokensFor(object: RemoteObject, style: RenderStyle = "value"): Token[] {
  switch (object.type) {
    case "string": {
      const text = typeof object.value === "string" ? object.value : (object.description ?? "")
      return style === "consoleArgument"
        ? [token(text, "plain")]
        : [token(quoted(text), "string")]
    }
    case "boolean":
      return [
        token(
          object.description ??
            (object.value === undefined ? "false" : displayString(object.value)),
          "boolean",
        ),
      ]
    case "number":
      return [token(numberString(object), "number")]
    case "undefined":
      return [token("undefined", "undefined")]
    case "symbol":
      return [token(object.description ?? "Symbol()", "symbol")]
    case "function":
      return [token(functionSummary(object.description), "function")]
    case "object":
      return objectTokens(object)
    default:
      // Hermes reports bigint as `type: ""` — the value is in description.
      return [
        token(
          object.description ??
            object.unserializableValue ??
            (object.value === undefined ? object.type : displayString(object.value)),
          "number",
        ),
      ]
  }
}

/**
 * The plain one-line summary — the tokens joined.
 *
 * Used for search and copy, so neither can diverge from what is on screen.
 */
export function inlineSummary(object: RemoteObject, style: RenderStyle = "value"): string {
  return tokensFor(object, style)
    .map((one) => one.text)
    .join("")
}

/** Whether a value has more to show if opened. */
export function isExpandable(object: RemoteObject): boolean {
  return object.objectId !== undefined && object.type === "object" && object.subtype !== "null"
}

/**
 * A whole `console.log(...)` argument list on one line.
 *
 * Only the *top-level* arguments render bare, which is why the style is passed
 * per argument rather than set once for the row: `console.log('a', {b: 'c'})`
 * is `a {b: 'c'}` — the nested string keeps its quotes.
 */
export function argumentSummary(args: readonly RemoteObject[]): string {
  return args.map((one) => inlineSummary(one, "consoleArgument")).join(" ")
}
