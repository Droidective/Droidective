import { cn } from "@/lib/cn"
import { inferKind, isComplete, needsBundle, type Draft } from "@/lib/custom-commands"

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
  const { kind, command } = inferKind(draft.command)

  return (
    <div className="flex flex-col gap-3 rounded-lg border border-border-subtle bg-bg-root p-3">
      <label className="flex flex-col gap-1">
        <span className="text-[12px] text-text-secondary">What it does</span>
        <input
          type="text"
          value={draft.name}
          placeholder="e.g. Restart app"
          onChange={(event) => onChange({ ...draft, name: event.target.value })}
          className="rounded border border-border-subtle bg-bg-surface px-2 py-1 text-text-primary placeholder:text-text-tertiary"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-[12px] text-text-secondary">Command</span>
        <textarea
          rows={3}
          value={draft.command}
          placeholder="adb shell am force-stop {bundleId}"
          onChange={(event) => onChange({ ...draft, command: event.target.value })}
          className="resize-y rounded border border-border-subtle bg-bg-surface px-2 py-1 font-mono text-[12px] text-text-primary placeholder:text-text-tertiary"
        />
        <span className="text-[11.5px] text-text-tertiary">
          {kind === "adb"
            ? `Runs as adb ${command === "" ? "…" : command}`
            : "Runs in your login shell."}
          {needsBundle(command) ? " Needs an app selected." : ""}
        </span>
      </label>

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
