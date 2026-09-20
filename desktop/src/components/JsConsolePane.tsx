import { useEffect, useMemo, useState } from "react"

import { Bar, Filters, Prompt } from "@/components/JsConsoleParts"
import { useJsConsole, DEFAULT_METRO_PORT } from "@/hooks/useJsConsole"
import { useNotifications } from "@/hooks/useNotifications"
import { asDaemonError, reactotronReverse, runAction } from "@/lib/daemon"
import { reloadMessage } from "@/lib/js-console-actions"
import { filtered, levelCounts, toggleLevel, type Level } from "@/lib/console-feed"
import { ConsoleFeed } from "@/components/ConsoleFeed"
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

  const { reloadJs } = console
  const reload = () => {
    void (async () => {
      const step = await reloadJs()
      // Hermes does not always implement `Page.reload`. The Mac falls back to
      // the device's own reload keys — which is `reload-js` in the registry,
      // the very same `input keyevent 46 46` — rather than reporting a failure
      // someone can do nothing about.
      if (step === "done" || device === null) {
        show({ message: reloadMessage(step, null), ok: step === "done" })
        return
      }
      const viaDevice = await runAction({
        featureId: "reload-js",
        serial: device.serial,
      }).then(
        (result) => ({ ok: result.ok }),
        () => ({ ok: false }),
      )
      show({ message: reloadMessage(step, viaDevice), ok: viaDevice.ok })
    })()
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <Bar
        console={console}
        port={port}
        onPort={setPort}
        serial={device?.serial ?? null}
        onReload={reload}
        onReport={show}
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
