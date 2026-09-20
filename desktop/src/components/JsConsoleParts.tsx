/**
 * The JS Console's chrome: the connection bar, the level filters and the
 * prompt.
 *
 * A sibling rather than part of `JsConsolePane` because that file is at
 * oxlint's dependency and line ceilings, which is the repo's cue to split.
 */

import { ChevronRight, Play, Plug, RefreshCw, RotateCw, Trash2 } from "lucide-react"

import { AppRestartMenu } from "@/components/AppRestartMenu"
import type { useJsConsole } from "@/hooks/useJsConsole"
import { DEFAULT_METRO_PORT } from "@/hooks/useJsConsole"
import { LEVELS, type Level } from "@/lib/console-feed"
import { consoleRestartTarget } from "@/lib/js-console-actions"
import { targetLabel } from "@/lib/metro"

export function Bar({
  console,
  port,
  onPort,
  serial,
  onReload,
  onReport,
  onReverse,
}: {
  console: ReturnType<typeof useJsConsole>
  port: number
  onPort: (port: number) => void
  serial: string | null
  onReload: () => void
  onReport: (outcome: { ok: boolean; message: string }) => void
  onReverse: (() => void) | null
}) {
  const connected = console.connection === "connected"
  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-border-subtle px-3 py-2">
      <span className="text-text-tertiary">Metro</span>
      <input
        type="number"
        aria-label="Metro port"
        value={port}
        onChange={(event) => onPort(Number(event.target.value) || DEFAULT_METRO_PORT)}
        // Never wider than it needs: nothing in this bar may demand more width
        // than the pane it sits in, or every row below is laid out too wide.
        className="w-16 rounded border border-border-subtle bg-bg-surface px-1.5 py-1 text-text-primary"
      />
      <select
        aria-label="Debug target"
        value={console.target?.id ?? ""}
        onChange={(event) => {
          const chosen = console.targets.find((one) => one.id === event.target.value)
          if (chosen !== undefined) console.connect(chosen)
        }}
        className="min-w-0 flex-1 truncate rounded border border-border-subtle bg-bg-surface px-2 py-1 text-text-primary"
      >
        <option value="">
          {console.targets.length === 0 ? "No targets" : "Pick a target…"}
        </option>
        {console.targets.map((one) => (
          <option key={one.id} value={one.id}>
            {targetLabel(one)}
          </option>
        ))}
      </select>
      <Status connection={console.connection} />
      <button
        type="button"
        title="Look for targets again"
        onClick={console.refresh}
        className="rounded p-1 text-text-secondary hover:bg-bg-surface"
      >
        <RotateCw size={13} />
      </button>
      {connected ? <ReloadButton onReload={onReload} /> : null}
      {serial === null ? null : (
        <AppRestartMenu
          serial={serial}
          // Metro names the app under debug, so there is nothing to guess at —
          // and nothing to guess *from* once the console disconnects.
          subject={consoleSubject(console)}
          onReport={onReport}
        />
      )}
      {onReverse === null ? null : <ReverseButton port={port} onReverse={onReverse} />}
    </div>
  )
}

function ReloadButton({ onReload }: { onReload: () => void }) {
  return (
    <button
      type="button"
      // The Mac's wording, which names the shortcut someone coming from RN
      // DevTools already knows. `Ctrl+R` rather than the Mac's `⌘R` is the
      // standing shortcut exception: React Native DevTools is a Chrome DevTools
      // frontend and binds Ctrl on the two platforms this build runs on, so the
      // Mac's key would name one nobody here has.
      title="Reload the JS bundle — what Ctrl+R in React Native DevTools does"
      onClick={onReload}
      className="flex shrink-0 items-center gap-1 rounded px-2 py-1 text-text-secondary hover:bg-bg-surface"
    >
      <RefreshCw size={13} />
      Reload JS
    </button>
  )
}

function ReverseButton({ port, onReverse }: { port: number; onReverse: () => void }) {
  return (
    <button
      type="button"
      // The Mac's label and its sentence, with "your Mac" as the standing
      // platform-name exception. It is *not* hidden while connected as the Mac
      // hides it: this console's own socket runs host-to-Metro and never
      // through the tunnel, so it stays connected while the device's route is
      // down — the shape of the bug #363 fixed for Reactotron. Raised against
      // the Mac rather than diverged from here.
      title={`Route the device's tcp:${String(port)} to Metro on this machine (USB devices)`}
      onClick={onReverse}
      className="flex shrink-0 items-center gap-1 rounded px-2 py-1 text-text-secondary hover:bg-bg-surface"
    >
      <Plug size={13} />
      adb reverse
    </button>
  )
}

/** The restart menu's subject: the debugged app's id, when Metro reported one. */
function consoleSubject(console: ReturnType<typeof useJsConsole>) {
  const target = consoleRestartTarget(
    console.connection === "connected" ? console.target?.appId ?? null : null,
  )
  return target.kind === "package"
    ? ({ kind: "package", packageId: target.packageId } as const)
    : ({ kind: "package", packageId: null } as const)
}

function Status({ connection }: { connection: string }) {
  const colour =
    connection === "connected"
      ? "bg-green-500"
      : connection === "connecting" || connection === "searching"
        ? "bg-amber-500"
        : connection === "failed"
          ? "bg-red-500"
          : "bg-text-tertiary"
  return (
    <span className="flex shrink-0 items-center gap-1 text-text-tertiary" title={connection}>
      <span className={`size-2 rounded-full ${colour}`} />
      {connection}
    </span>
  )
}

export function Filters({
  levels,
  counts,
  query,
  onQuery,
  onToggle,
  onClear,
}: {
  levels: ReadonlySet<Level>
  counts: Record<Level, number>
  query: string
  onQuery: (value: string) => void
  onToggle: (level: Level) => void
  onClear: () => void
}) {
  return (
    <div className="flex shrink-0 items-center gap-1 border-b border-border-subtle px-3 py-1.5">
      {LEVELS.map((level) => (
        <button
          key={level}
          type="button"
          onClick={() => onToggle(level)}
          // Nothing ticked means everything, so the unticked state is not "off".
          className={`rounded px-1.5 py-0.5 capitalize ${
            levels.has(level)
              ? "bg-accent/20 text-text-primary"
              : "text-text-tertiary hover:bg-bg-surface"
          }`}
        >
          {level} {counts[level] > 0 ? counts[level] : ""}
        </button>
      ))}
      <input
        value={query}
        placeholder="Filter…"
        onChange={(event) => onQuery(event.target.value)}
        className="ml-1 min-w-0 flex-1 rounded border border-border-subtle bg-bg-surface px-2 py-1 text-text-primary"
      />
      <button
        type="button"
        title="Clear the console and release the logged objects"
        onClick={onClear}
        className="rounded p-1 text-text-secondary hover:bg-bg-surface"
      >
        <Trash2 size={13} />
      </button>
    </div>
  )
}

export function Prompt({
  value,
  enabled,
  onChange,
  onSubmit,
}: {
  value: string
  enabled: boolean
  onChange: (value: string) => void
  onSubmit: () => void
}) {
  return (
    <div className="flex shrink-0 items-center gap-2 border-t border-border-subtle px-3 py-2">
      <ChevronRight size={13} className="shrink-0 text-text-tertiary" />
      <input
        value={value}
        disabled={!enabled}
        placeholder={enabled ? "Evaluate JavaScript in the app…" : "Connect to a target first"}
        onChange={(event) => onChange(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter") onSubmit()
        }}
        className="min-w-0 flex-1 bg-transparent font-mono text-text-primary outline-none disabled:opacity-50"
      />
      <button
        type="button"
        disabled={!enabled}
        onClick={onSubmit}
        className="shrink-0 rounded p-1 text-text-secondary hover:bg-bg-surface disabled:opacity-40"
      >
        <Play size={13} />
      </button>
    </div>
  )
}
