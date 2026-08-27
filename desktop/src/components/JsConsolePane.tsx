import { ChevronRight, Play, Plug, RotateCw, Trash2 } from "lucide-react"
import { useEffect, useMemo, useState } from "react"

import { useJsConsole, DEFAULT_METRO_PORT } from "@/hooks/useJsConsole"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, reactotronReverse } from "@/lib/daemon"
import {
  filtered,
  LEVELS,
  levelCounts,
  toggleLevel,
  type Level,
} from "@/lib/console-feed"
import { ConsoleFeed } from "@/components/ConsoleFeed"
import { targetLabel } from "@/lib/metro"
import type { Device } from "@/lib/wire"

/**
 * JS Console — the Mac's `JSConsoleView`.
 *
 * A Hermes Chrome-DevTools-Protocol console for React Native: Metro's target
 * list, a live feed, and a prompt. The device needs `adb reverse` to reach
 * Metro, which is the one thing here that goes through the daemon.
 *
 * The socket itself is the webview's — see `useJsConsole` for why.
 */
export function JsConsolePane({ device }: { device: Device | null }) {
  const [port, setPort] = useState(DEFAULT_METRO_PORT)
  const console = useJsConsole(port)
  const { show } = useNotifications()
  const [levels, setLevels] = useState<ReadonlySet<Level>>(new Set())
  const [query, setQuery] = useState("")
  const [draft, setDraft] = useState("")

  const { refresh } = console
  useEffect(() => {
    refresh()
  }, [refresh])

  const shown = useMemo(() => filtered(console.rows, { levels, query }), [console.rows, levels, query])
  const counts = useMemo(() => levelCounts(console.rows), [console.rows])

  const reverse = () => {
    const serial = device?.serial
    if (serial === undefined) return
    void (async () => {
      try {
        await reactotronReverse([serial], port)
        show({ message: `Forwarded port ${String(port)} to the device.`, ok: true })
        refresh()
      } catch (thrown) {
        show({ message: asDaemonError(thrown).message, ok: false })
      }
    })()
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <Bar
        console={console}
        port={port}
        onPort={setPort}
        onReverse={device === null ? null : reverse}
      />
      <Filters
        levels={levels}
        counts={counts}
        query={query}
        onQuery={setQuery}
        onToggle={(level) => setLevels((current) => toggleLevel(current, level))}
        onClear={console.clear}
      />
      <ConsoleFeed
        rows={shown}
        empty={console.rows.length === 0}
        problem={console.problem}
        connection={console.connection}
        targetCount={console.targets.length}
      />
      <Prompt
        value={draft}
        enabled={console.connection === "connected"}
        onChange={setDraft}
        onSubmit={() => {
          console.evaluate(draft)
          setDraft("")
        }}
      />
    </div>
  )
}

function Bar({
  console,
  port,
  onPort,
  onReverse,
}: {
  console: ReturnType<typeof useJsConsole>
  port: number
  onPort: (port: number) => void
  onReverse: (() => void) | null
}) {
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
      {onReverse === null ? null : (
        <button
          type="button"
          title="adb reverse — let the device reach Metro on this machine"
          onClick={onReverse}
          className="flex items-center gap-1 rounded px-2 py-1 text-text-secondary hover:bg-bg-surface"
        >
          <Plug size={13} />
          Reverse
        </button>
      )}
    </div>
  )
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

function Filters({
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

function Prompt({
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
