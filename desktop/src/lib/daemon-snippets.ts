import { invoke } from "@tauri-apps/api/core"

import type { Snippet } from "@/lib/snippets"

/**
 * The saved Send Text snippets, and filling a snippet's live values in.
 *
 * Its own module rather than another entry in `daemon-settings`: those calls
 * read and write one *device*, and these read and write this machine's store.
 * Re-exported from `@/lib/daemon`, so nothing about the import moved.
 */

/**
 * The saved Send Text snippets.
 *
 * The store is the Mac's own `presets.json`, under the shared support dir, so
 * a developer running both apps has one set. The write is a verb rather than a
 * whole list because the rules that make a snippet — the clamped name, the
 * uniqueness check, the use-count bump that ranks the quick-insert row — are
 * `Presets`' own methods, and a client re-deriving them would drift.
 */
export function snippets(): Promise<Snippet[]> {
  return invoke<Snippet[]>("snippets")
}

export function writeSnippet(args: {
  op: "add" | "remove" | "use"
  name: string
  text?: string
}): Promise<Snippet[]> {
  return invoke<Snippet[]>("write_snippet", { ...args, text: args.text ?? null })
}

/**
 * A snippet's text with `{clipboard}` and `{ip}` filled in.
 *
 * The clipboard is read in the Rust process, because the daemon is headless
 * and has none; the substitution itself is ADBKit's `SnippetPlaceholders`, so
 * both apps expand the same way — including its rule that a substituted value
 * is never re-scanned.
 */
export function expandSnippet(text: string): Promise<{ text: string; hostIp: string | null }> {
  return invoke<{ text: string; hostIp: string | null }>("expand_snippet", { text })
}
