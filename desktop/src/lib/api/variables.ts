/**
 * `{{variable}}` resolution — `ADBKit/Services/ApiClient/ApiVariables.swift`,
 * ported as far as this side needs it.
 *
 * The *send* resolves daemon-side, where the dynamic values (`{{$guid}}` and
 * friends) are generated. What is here is the half the editor needs while
 * someone types: which layer a name comes from, and which names have nothing
 * to come from — the strip under the URL bar updates on every keystroke, and a
 * round trip per character would be a network call per character.
 */

import { activeMap } from "@/lib/api/defaults"
import type { ApiClientData, ApiCollection, SavedRequest } from "@/lib/api/model"

/** The four layers, highest precedence last. */
export interface VariableScope {
  globals: Record<string, string>
  environment: Record<string, string>
  collection: Record<string, string>
  local: Record<string, string>
}

export const EMPTY_SCOPE: VariableScope = {
  globals: {},
  environment: {},
  collection: {},
  local: {},
}

/** Flattened lookup with precedence applied. */
export function merged(scope: VariableScope): Record<string, string> {
  return { ...scope.globals, ...scope.environment, ...scope.collection, ...scope.local }
}

/** Which layer a name resolves from, for a tooltip. */
export function origin(scope: VariableScope, name: string): string | null {
  if (name in scope.local) return "request"
  if (name in scope.collection) return "collection"
  if (name in scope.environment) return "environment"
  if (name in scope.globals) return "global"
  return null
}

/** The scope a request opened from `collection` runs in. */
export function scopeFor(data: ApiClientData, collection: ApiCollection | null): VariableScope {
  const environment = data.environments.find((one) => one.id === data.activeEnvironmentId)
  return {
    globals: activeMap(data.globals),
    environment: environment === undefined ? {} : activeMap(environment.variables),
    collection: collection === null ? {} : activeMap(collection.variables),
    local: {},
  }
}

/** Recursion cap — `ApiVariables.maxDepth`. */
const MAX_DEPTH = 10

/** Ceiling on an expanded string — `ApiVariables.maxExpandedBytes`. */
const MAX_EXPANDED_BYTES = 1 << 20

/** The `{{$…}}` names, which resolve at send time rather than here. */
const DYNAMIC_NAMES = ["$guid", "$randomUUID", "$timestamp", "$isoTimestamp", "$randomInt"]

/**
 * One substitution pass.
 *
 * A lookup returning null leaves the reference written as it was, which is
 * what makes an unknown variable *visible* rather than silently an empty
 * string. Ported reference-faithfully, nesting rule included: `{{a{{b}}}}`
 * expands nothing, because a name containing another opener is not a name.
 */
export function expandOnce(template: string, lookup: (name: string) => string | null): string {
  if (!template.includes("{{")) return template
  let out = ""
  let rest = template

  for (;;) {
    const open = rest.indexOf("{{")
    if (open < 0) break
    out += rest.slice(0, open)
    const afterOpen = rest.slice(open + 2)
    const close = afterOpen.indexOf("}}")
    if (close < 0) {
      out += rest.slice(open)
      return out
    }
    const rawName = afterOpen.slice(0, close)
    const name = rawName.trim()
    if (name === "" || rawName.includes("{{")) {
      out += "{{"
      rest = afterOpen
      continue
    }
    const value = lookup(name)
    out += value === null ? `{{${rawName}}}` : value
    rest = afterOpen.slice(close + 2)
  }
  return out + rest
}

/** Substitutes from `scope`, then re-expands what the values themselves hold. */
export function resolve(template: string, scope: VariableScope): string {
  if (!template.includes("{{")) return template
  const map = merged(scope)
  let current = template
  for (let round = 0; round < MAX_DEPTH; round += 1) {
    const next = expandOnce(current, (name) => map[name] ?? null)
    if (next === current) break
    if (next.length > MAX_EXPANDED_BYTES) return next
    current = next
  }
  return current
}

/**
 * Names still written as `{{name}}` after resolution.
 *
 * The dynamic names are excluded: they resolve at send time, so listing them
 * would warn about the one kind of variable that always works.
 */
export function unresolvedNames(template: string, scope: VariableScope): string[] {
  const resolved = resolve(template, scope)
  const names: string[] = []
  expandOnce(resolved, (name) => {
    if (!names.includes(name) && !DYNAMIC_NAMES.includes(name)) names.push(name)
    return null
  })
  return names
}

/**
 * Every unresolved name across a request, for the strip under the URL bar.
 *
 * The same fields `ApiVariables.unresolvedNames(in:scope:)` scans, in the same
 * order, so the two apps warn about the same things — including the detail
 * that a disabled header is not scanned, because it is not sent.
 */
export function unresolvedInRequest(request: SavedRequest, scope: VariableScope): string[] {
  const names: string[] = []
  const scan = (text: string) => {
    for (const name of unresolvedNames(text, scope)) {
      if (!names.includes(name)) names.push(name)
    }
  }

  scan(request.url)
  for (const pair of request.headers) {
    if (!pair.enabled) continue
    scan(pair.key)
    scan(pair.value)
  }
  for (const pair of request.queryParams) {
    if (!pair.enabled) continue
    scan(pair.key)
    scan(pair.value)
  }
  for (const pair of request.pathVariables) scan(pair.value)

  const body = request.body
  switch (body.type) {
    case "json":
      scan(body.jsonText)
      break
    case "raw":
      scan(body.rawText)
      break
    case "formUrlEncoded":
      for (const field of body.formFields) {
        if (!field.enabled) continue
        scan(field.key)
        scan(field.value)
      }
      break
    case "multipart":
      for (const field of body.multipartFields) {
        if (!field.enabled) continue
        scan(field.key)
        scan(field.value)
      }
      break
    case "graphql":
      scan(body.graphqlQuery)
      scan(body.graphqlVariables)
      break
    case "binary":
      scan(body.binaryFilePath)
      break
    case "none":
      break
  }

  scan(request.auth.bearerToken)
  scan(request.auth.basicUsername)
  scan(request.auth.basicPassword)
  scan(request.auth.apiKeyName)
  scan(request.auth.apiKeyValue)
  scan(request.auth.oauth2Token)
  return names
}
