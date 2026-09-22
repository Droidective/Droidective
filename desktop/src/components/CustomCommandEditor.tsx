import { useEffect } from "react"
import { FileCog } from "lucide-react"

import { hasModifier } from "@/lib/platform"
import { cn } from "@/lib/cn"
import { pickFile } from "@/lib/daemon"
import { inferKind, isComplete, needsBundle, withScript, type Draft } from "@/lib/custom-commands"

/**
 * The editor for one command — the Mac's sheet, inline.
 *
 * The kind is shown rather than chosen: a leading `adb` decides it, so a picker
 * would be a second way to say the same thing and the two could disagree. Same
 * for whether it needs an app, which `{bundleId}` decides.
 */
export function CustomCommandEditor({
  draft,
  onChange,
  onSave,
  onCancel,
  busy,
}: {
  draft: Draft
  onChange: (draft: Draft) => void
  onSave: () => void
  onCancel: () => void
  busy: boolean
}) {
  useEditorKeys({ onCancel, onSave, busy })

  return (
    <div className="flex flex-col gap-3 rounded-lg border border-border-subtle bg-bg-root p-3">
      <label className="flex flex-col gap-1">
        <span className="text-[12px] text-text-secondary">What it does</span>
        <input
          type="text"
          value={draft.name}
          placeholder="What it does — e.g. Restart app"
          onChange={(event) => onChange({ ...draft, name: event.target.value })}
          className="rounded border border-border-subtle bg-bg-surface px-2 py-1 text-text-primary placeholder:text-text-tertiary"
        />
      </label>

      <CommandField draft={draft} onChange={onChange} />

      <label className="flex items-center gap-3">
        <span className="w-28 shrink-0 text-[12px] text-text-secondary">Show output</span>
        <select
          value={draft.runsInTerminal ? "terminal" : "silent"}
          onChange={(event) =>
            onChange({ ...draft, runsInTerminal: event.target.value === "terminal" })
          }
          className="rounded border border-border-subtle bg-bg-surface px-2 py-1 text-text-primary"
        >
          <option value="silent">Silently, with a result</option>
          <option value="terminal">In a terminal</option>
        </select>
      </label>

      {draft.runsInTerminal && (
        <label className="flex items-center gap-3">
          <span className="w-28 shrink-0 text-[12px] text-text-secondary">Terminal</span>
          <select
            value={draft.terminal}
            onChange={(event) => onChange({ ...draft, terminal: event.target.value })}
            className="rounded border border-border-subtle bg-bg-surface px-2 py-1 text-text-primary"
          >
            <option value="droidective">Droidective</option>
            <option value="default">Your default terminal</option>
          </select>
        </label>
      )}

      <div className="flex items-center gap-2">
        <button
          type="button"
          disabled={busy || !isComplete(draft)}
          onClick={onSave}
          className={cn(
            "rounded bg-accent px-3 py-1 text-white",
            "disabled:cursor-not-allowed disabled:opacity-40",
          )}
        >
          Save
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded border border-border-subtle px-3 py-1 text-text-primary hover:bg-bg-hover"
        >
          Cancel
        </button>
      </div>
    </div>
  )
}

/**
 * The command itself, and the picker that fills it in.
 *
 * The routing cue under the field is live: the leading token decides whether
 * the line is tokenized into an adb argv or handed to a login shell, so it is
 * shown rather than chosen — a picker would be a second way to say the same
 * thing, and the two could disagree.
 */
function CommandField({
  draft,
  onChange,
}: {
  draft: Draft
  onChange: (draft: Draft) => void
}) {
  const { kind, command } = inferKind(draft.command)

  return (
      <label className="flex flex-col gap-1">
        <span className="text-[12px] text-text-secondary">Command</span>
        <div className="flex items-start gap-2">
          <textarea
            rows={3}
            value={draft.command}
            placeholder="adb shell am force-stop {bundleId}"
            onChange={(event) => onChange({ ...draft, command: event.target.value })}
            className="min-w-0 flex-1 resize-y rounded border border-border-subtle bg-bg-surface px-2 py-1 font-mono text-[12px] text-text-primary placeholder:text-text-tertiary"
          />
          <button
            type="button"
            title="Choose a script or executable to run"
            aria-label="Choose a script or executable to run"
            onClick={() => {
              void pickFile("Script or executable", []).then((path) => {
                // A dismissed picker is a choice, not a failure.
                if (path !== null) onChange({ ...draft, command: withScript(path, draft.command) })
              })
            }}
            className="shrink-0 rounded border border-border-subtle p-1.5 text-text-secondary hover:bg-bg-hover hover:text-text-primary"
          >
            <FileCog size={14} />
          </button>
        </div>
        <span className="text-[11.5px] text-text-tertiary">
          {kind === "adb"
            ? `Runs as adb ${command === "" ? "…" : command}`
            : "Runs in your login shell."}
          {needsBundle(command) ? " Needs an app selected." : ""}
        </span>
      </label>
  )
}

/**
 * The editor's two chords, the Mac's.
 *
 * Escape discards; the accelerator and Return save. Return *alone* is not
 * enough — the command field is multi-line, and a bare Return there belongs to
 * the command being written.
 */
function useEditorKeys(args: { onCancel: () => void; onSave: () => void; busy: boolean }): void {
  const { onCancel, onSave, busy } = args
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault()
        onCancel()
        return
      }
      if (event.key === "Enter" && hasModifier(event) && !busy) {
        event.preventDefault()
        onSave()
      }
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [onCancel, onSave, busy])
}
