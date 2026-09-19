import { RefreshCw, Trash2 } from "lucide-react"
import { useCallback, useEffect, useState } from "react"
import { ConfirmDialog } from "@/components/ConfirmDialog"
import { Button } from "@/components/Controls"
import { IconButton } from "@/components/Hub"
import { exitLabel, hasOutput, succeeded, timeLabel } from "@/lib/commandlog"
import { asDaemonError, clearCommandLog, commandLog } from "@/lib/daemon"
import type { CommandLogEntry, DaemonError } from "@/lib/wire"

/**
 * The Mac's `CommandLogView`, opened from Settings ▸ Privacy.
 *
 * An expandable list of the recent user-initiated adb calls: the command, its
 * exit code and duration, and its output when a row is opened. The daemon
 * decides what is in it — see `CommandLogProtocol` — so this only renders.
 */
export function CommandLogSheet({ onDismiss }: { onDismiss: () => void }) {
  const [entries, setEntries] = useState<CommandLogEntry[]>([])
  const [error, setError] = useState<DaemonError | null>(null)
  const [confirmClear, setConfirmClear] = useState(false)

  const refresh = useCallback(async () => {
    try {
      setEntries((await commandLog()).entries)
      setError(null)
    } catch (thrown) {
      setError(asDaemonError(thrown))
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // Escape closes — but not while the clear dialog is up, which owns it.
      if (event.key === "Escape" && !confirmClear) onDismiss()
    }
    globalThis.addEventListener("keydown", onKeyDown)
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown)
    }
  }, [confirmClear, onDismiss])

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-8">
      <button
        type="button"
        aria-label="Dismiss"
        onClick={onDismiss}
        className="absolute inset-0 cursor-default"
      />
      <div className="relative flex h-[420px] w-[560px] max-w-full flex-col rounded-xl border border-border-subtle bg-bg-raised shadow-2xl">
        <header className="flex items-center gap-2 border-b border-border-subtle px-3 py-3">
          <h2 className="min-w-0 flex-1 text-[15px] font-medium text-text-primary">Command Log</h2>
          <IconButton icon={<RefreshCw size={14} />} label="Refresh" onClick={() => void refresh()} />
          <IconButton
            icon={<Trash2 size={14} />}
            label="Clear command log"
            onClick={() => {
              setConfirmClear(true)
            }}
          />
          <Button onClick={onDismiss}>Close</Button>
        </header>

        <div className="min-h-0 flex-1 overflow-auto" data-selectable>
          <Body entries={entries} error={error} />
        </div>
      </div>

      {confirmClear ? (
        <ConfirmDialog
          title="Clear the command log?"
          message="This removes all recorded commands."
          confirmLabel="Clear"
          onCancel={() => {
            setConfirmClear(false)
          }}
          onConfirm={() => {
            setConfirmClear(false)
            void clearCommandLog()
              .then(refresh)
              .catch((thrown: unknown) => {
                setError(asDaemonError(thrown))
              })
          }}
        />
      ) : null}
    </div>
  )
}

function Body({ entries, error }: { entries: CommandLogEntry[]; error: DaemonError | null }) {
  if (error !== null) {
    return <p className="p-4 text-[12.5px] text-danger">{error.message}</p>
  }
  if (entries.length === 0) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-1 px-8 text-center">
        <p className="text-[13px] text-text-secondary">No commands yet</p>
        <p className="text-[11.5px] text-text-tertiary">
          Commands you run appear here with their output.
        </p>
      </div>
    )
  }
  return (
    <ul className="flex flex-col">
      {entries.map((entry) => (
        <Row key={entry.id} entry={entry} />
      ))}
    </ul>
  )
}

function Row({ entry }: { entry: CommandLogEntry }) {
  const [expanded, setExpanded] = useState(false)
  return (
    <li className="border-b border-border-subtle/60 px-3 py-1.5">
      <button
        type="button"
        aria-expanded={expanded}
        onClick={() => {
          setExpanded((open) => !open)
        }}
        className="flex w-full items-baseline gap-1.5 text-left"
      >
        <span className="shrink-0 text-[10px] text-text-tertiary">{expanded ? "▾" : "▸"}</span>
        <span
          className={
            expanded
              ? "min-w-0 flex-1 break-all font-mono text-[12px] text-text-primary"
              : "min-w-0 flex-1 truncate font-mono text-[12px] text-text-primary"
          }
        >
          {entry.command}
        </span>
        <span
          className={
            succeeded(entry)
              ? "shrink-0 text-[11px] text-accent"
              : "shrink-0 text-[11px] text-danger"
          }
        >
          {exitLabel(entry)}
        </span>
        <span className="shrink-0 text-[11px] text-text-tertiary">{timeLabel(entry.at)}</span>
      </button>

      {expanded ? (
        <div className="mt-1 flex flex-col gap-1 pl-[18px]">
          {entry.stdout.length === 0 ? null : <Output text={entry.stdout} />}
          {entry.stderr.length === 0 ? null : <Output text={entry.stderr} tone="danger" />}
          {hasOutput(entry) ? null : (
            <p className="text-[11px] text-text-tertiary">(no output)</p>
          )}
        </div>
      ) : null}
    </li>
  )
}

function Output({ text, tone = "plain" }: { text: string; tone?: "plain" | "danger" }) {
  return (
    <pre
      className={
        tone === "danger"
          ? "max-h-40 overflow-auto whitespace-pre-wrap break-all rounded bg-danger/10 p-1.5 font-mono text-[11px] text-danger"
          : "max-h-40 overflow-auto whitespace-pre-wrap break-all rounded bg-text-tertiary/15 p-1.5 font-mono text-[11px] text-text-primary"
      }
    >
      {text}
    </pre>
  )
}
