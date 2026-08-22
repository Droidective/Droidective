/**
 * The JSON value a Reactotron payload is, and the two things done to one before
 * anything renders it: undoing the client's sentinel encoding, and previewing it
 * without walking it.
 *
 * ADBKit's twin is `JSONValue` + `repairingSentinels()`. The enum itself does
 * not come across — Swift needs a tagged union to hold an arbitrary payload and
 * TypeScript already has one, so a `case .string(let text)` becomes
 * `typeof value === "string"` and nothing is lost. Every *decision* the Swift
 * makes is here, and the tests are the same tests.
 */

export type JsonValue = null | boolean | number | string | JsonValue[] | JsonObject
export interface JsonObject {
  [key: string]: JsonValue
}

export function isJsonObject(value: JsonValue): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

/** A field of `value`, or undefined when it is not an object that has one. */
export function field(value: JsonValue | undefined, key: string): JsonValue | undefined {
  if (value === undefined || !isJsonObject(value)) return undefined
  return value[key]
}

export function stringField(value: JsonValue | undefined, key: string): string | undefined {
  const found = field(value, key)
  return typeof found === "string" ? found : undefined
}

export function numberField(value: JsonValue | undefined, key: string): number | undefined {
  const found = field(value, key)
  return typeof found === "number" ? found : undefined
}

export function arrayField(value: JsonValue | undefined, key: string): JsonValue[] | undefined {
  const found = field(value, key)
  return Array.isArray(found) ? found : undefined
}

/**
 * Longest sentinel worth inspecting. Past this the string is a payload that
 * happens to start with tildes, and lowercasing it to find out costs a copy.
 */
const maxSentinelLength = 2048

/**
 * Undo the Reactotron client's sentinel encoding — the mirror of
 * `reactotron-core-server`'s `repair-serialization.ts`, which runs on every
 * inbound payload.
 *
 * The client serializes JSON-hostile values as `"~~~ … ~~~"` marker strings.
 * The named falsy markers map back to their real values (case-insensitively,
 * like the original); any other marker — a function, a circular reference,
 * Infinity — drops its tildes and stays a string.
 *
 * An untouched subtree is returned as-is rather than rebuilt, so a clean
 * payload costs one walk and no allocation. That is why the recursion returns
 * `undefined` for "nothing to repair here": `null` is a real repair result, so
 * it cannot double as the sentinel.
 */
export function repairSentinels(value: JsonValue): JsonValue {
  // Compared against `undefined` rather than written `repaired(value) ?? value`:
  // `??` is nullish, so it would treat a repaired `null` — which is what
  // "~~~ null ~~~" becomes — as "nothing to repair" and hand back the marker
  // text. Exactly the confusion the two-value convention exists to keep apart.
  const fixed = repaired(value)
  return fixed === undefined ? value : fixed
}

function repaired(value: JsonValue): JsonValue | undefined {
  if (typeof value === "string") return repairedSentinel(value)
  if (Array.isArray(value)) {
    let copy: JsonValue[] | undefined
    for (const [index, item] of value.entries()) {
      const fixed = repaired(item)
      if (fixed === undefined) continue
      copy ??= [...value]
      copy[index] = fixed
    }
    return copy
  }
  if (isJsonObject(value)) {
    let copy: JsonObject | undefined
    for (const [key, item] of Object.entries(value)) {
      const fixed = repaired(item)
      if (fixed === undefined) continue
      copy ??= { ...value }
      copy[key] = fixed
    }
    return copy
  }
  return undefined
}

function repairedSentinel(text: string): JsonValue | undefined {
  // Markers are short ("~~~ name() ~~~"); the length guard keeps the
  // lowercasing off megabyte log strings. > 9 matches the original's repair
  // threshold.
  if (text.length <= 9 || text.length >= maxSentinelLength) return undefined
  if (!text.startsWith("~~~ ") || !text.endsWith(" ~~~")) return undefined
  switch (text.toLowerCase()) {
    case "~~~ null ~~~":
      return null
    // JSON has no undefined; null is the closest honest value.
    case "~~~ undefined ~~~":
      return null
    case "~~~ false ~~~":
      return false
    case "~~~ zero ~~~":
      return 0
    case "~~~ empty string ~~~":
      return ""
    default:
      return text.slice(4, -4)
  }
}

/**
 * A bounded compact-JSON preview: reads like `JSON.stringify` with sorted keys,
 * but STOPS serializing once `maxLength` characters are produced.
 *
 * Previewing a row therefore costs O(maxLength) however big the payload is —
 * `JSON.stringify` walks the whole value, which stalls the feed on a
 * multi-megabyte `console.log`. The result may cut off mid-token; it is a
 * preview, not valid JSON.
 */
export function compactPreview(value: JsonValue, maxLength: number): string {
  const out: string[] = []
  appendCompact(value, out, { remaining: maxLength })
  return out.join("")
}

/** Past this many keys, sorting for a stable preview stops being worth it. */
const sortKeysUpTo = 128

interface Budget {
  remaining: number
}

function appendCompact(value: JsonValue, out: string[], budget: Budget): void {
  if (budget.remaining <= 0) return
  const emit = (chunk: string) => {
    const piece = chunk.length <= budget.remaining ? chunk : chunk.slice(0, budget.remaining)
    out.push(piece)
    budget.remaining -= piece.length
  }
  // `String` covers null, the booleans and the numbers between them. ADBKit
  // formats numbers by hand only because Swift prints a whole `Double` as
  // "2.0"; JavaScript already prints "2", so there is nothing to correct.
  if (value === null || typeof value === "boolean" || typeof value === "number") {
    emit(String(value))
    return
  }
  if (typeof value === "string") {
    emit('"')
    emit(escapeForPreview(value, budget.remaining))
    emit('"')
    return
  }
  if (Array.isArray(value)) {
    emit("[")
    for (const [index, item] of value.entries()) {
      if (budget.remaining <= 0) return
      if (index > 0) emit(",")
      appendCompact(item, out, budget)
    }
    emit("]")
    return
  }
  emit("{")
  // Sorted keys make the preview stable, but sorting a pathological
  // 100k-key object is not worth it once nothing human is reading every key.
  const keys = Object.keys(value)
  if (keys.length <= sortKeysUpTo) keys.sort()
  for (const [index, key] of keys.entries()) {
    if (budget.remaining <= 0) return
    if (index > 0) emit(",")
    emit('"')
    emit(escapeForPreview(key, budget.remaining))
    emit('":')
    appendCompact(value[key] ?? null, out, budget)
  }
  emit("}")
}

/**
 * Minimal JSON string escaping over at most `maxLength` characters of input —
 * never walks a megabyte string to preview its head.
 */
function escapeForPreview(text: string, maxLength: number): string {
  let out = ""
  for (const character of text.slice(0, Math.max(0, maxLength))) {
    switch (character) {
      case '"':
        out += '\\"'
        break
      case "\\":
        out += "\\\\"
        break
      case "\n":
        out += "\\n"
        break
      case "\r":
        out += "\\r"
        break
      case "\t":
        out += "\\t"
        break
      default:
        out += character
    }
  }
  return out
}
