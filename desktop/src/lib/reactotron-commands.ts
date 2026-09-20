/** The custom-commands screen's decisions. See `reactotron-repl.ts` on why
 * these live apart from `reactotron-state.ts`. */
import { isJsonObject, type JsonObject, type JsonValue } from "@/lib/json"
import type { Outgoing } from "@/lib/reactotron-state"

/** One button an app registered with `Reactotron.onCustomCommand(...)`. */
export interface CustomCommand {
  id: number
  command: string
  title: string | null
  description: string | null
  /** Each argument's name; the contract leaves `type` open but it is always a string. */
  args: string[]
}

/**
 * Fire one, with whatever was typed into its fields.
 *
 * Every declared argument is sent, blank ones included: the client indexes the
 * object by name, and an omitted key arrives as `undefined` where the app
 * expected an empty string.
 */
export function runCustomCommand(
  command: CustomCommand,
  values: Readonly<Record<string, string>>,
): Outgoing {
  const args: Record<string, JsonValue> = {}
  for (const name of command.args) args[name] = values[name] ?? ""
  return { kind: "custom", payload: { command: command.command, args } }
}

/** What a register/unregister does to the button list. */
export type CommandEvent =
  | { kind: "register"; command: CustomCommand }
  | { kind: "unregister"; id: number }
  | null

export function readCommandEvent(type: string, payload: unknown): CommandEvent {
  const body = asObject(payload)
  if (body === null) return null
  if (type === "customCommand.register") {
    const command = body["command"]
    if (typeof command !== "string" || command === "") return null
    const rawArgs = body["args"]
    return {
      kind: "register",
      command: {
        id: typeof body["id"] === "number" ? body["id"] : 0,
        command,
        title: typeof body["title"] === "string" ? body["title"] : null,
        description: typeof body["description"] === "string" ? body["description"] : null,
        args: Array.isArray(rawArgs)
          ? rawArgs
              .map((arg) => asObject(arg)?.["name"])
              .filter((name): name is string => typeof name === "string" && name !== "")
          : [],
      },
    }
  }
  if (type === "customCommand.unregister") {
    const id = body["id"]
    return typeof id === "number" ? { kind: "unregister", id } : null
  }
  return null
}

/**
 * Fold a register into the list.
 *
 * Replaces rather than appends when the id is already known: a reloaded app
 * re-registers everything it has, and appending would show every button twice
 * after a Fast Refresh.
 */
export function withCommand(
  commands: readonly CustomCommand[],
  command: CustomCommand,
): CustomCommand[] {
  const at = commands.findIndex((existing) => existing.id === command.id)
  if (at === -1) return [...commands, command]
  return commands.map((existing, index) => (index === at ? command : existing))
}

export function withoutCommand(
  commands: readonly CustomCommand[],
  id: number,
): CustomCommand[] {
  return commands.filter((command) => command.id !== id)
}

/** A payload as an object, or nothing — `reactotron-state.ts` keeps its own. */
function asObject(value: unknown): JsonObject | null {
  const json = value as JsonValue
  return isJsonObject(json) ? json : null
}
